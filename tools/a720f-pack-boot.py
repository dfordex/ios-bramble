#!/usr/bin/env python3
"""Repack an SM-A720F BOOT candidate around shim/a720f Images (probe or XNU loader).

Adapted from a5xelte-pack-probe.py.

Host-side only. Never opens a block device and never flashes the phone.
The reference BOOT may contain private data; keep it and the output off Git.
"""
import argparse
import hashlib
from pathlib import Path
import struct


# SM-A720F / A720FXXU9CSK3. The initrd destination is TWRP's live
# /chosen/linux,initrd-start. The staging base is NOT observed: it assumes
# S-Boot stages the image one 2 KiB header page below the stock kernel's
# 0x40000000 + text_offset 0x1000, as on the A5 (0x40204800 for 0x205000).
# The stage-0 probe logs the real Image address; correct this from it.
SBOOT_IMAGE_STAGING_BASE = 0x40000800
SBOOT_INITRD_DEST = 0x42200000
SBOOT_DT_ID = (7880, 0x50A6, 0x217584DA)
SBOOT_HW_REV = 6     # androidboot.hw_rev=6 -> DTBH entry hwrev 6-255
IMAGE_TEXT_OFFSET = 0x1000


def dtbh_entries(dt):
    """Validate every declared blob, including padding and disjoint ranges."""
    if len(dt) < 12 or dt[:4] != b"DTBH" or struct.unpack_from("<I", dt, 4)[0] != 2:
        raise ValueError("reference DTBH version is not the observed format")
    count = struct.unpack_from("<I", dt, 8)[0]
    table_end = 12 + count * 32
    if not 1 <= count <= 32 or table_end > len(dt):
        raise ValueError("invalid DTBH table")
    entries = []
    for index in range(count):
        entry = struct.unpack_from("<8I", dt, 12 + index * 32)
        offset, size = entry[5:7]
        if offset < table_end or size < 40 or offset > len(dt) or size > len(dt) - offset:
            raise ValueError(f"DTBH entry{index} offset/size exceeds its bounded data region")
        magic, total = struct.unpack_from(">2I", dt, offset)
        if magic != 0xD00DFEED or total < 40 or total > size:
            raise ValueError(f"DTBH entry{index} FDT magic/total size rejected")
        entries.append(entry)
    ranges = sorted((entry[5], entry[5] + entry[6]) for entry in entries)
    if any(left[1] > right[0] for left, right in zip(ranges, ranges[1:])):
        raise ValueError("overlapping DTBH blob ranges cannot be repacked safely")
    return entries


def selected_entry(entry):
    return entry[:3] == SBOOT_DT_ID and entry[3] <= SBOOT_HW_REV <= entry[4]


def validate_sboot_staging(kernel_size, ramdisk_size, dt, page=2048):
    """Reject selected FDT sources that initrd relocation could overwrite."""
    if page != 2048 or kernel_size <= 0 or ramdisk_size <= 0:
        raise ValueError("unsupported observed Samsung staging layout")
    entries = dtbh_entries(dt)
    align = lambda size: (size + page - 1) // page * page
    dt_image_offset = page + align(kernel_size) + align(ramdisk_size)
    selected = []
    for index, entry in enumerate(entries):
        if not selected_entry(entry):
            continue
        start = SBOOT_IMAGE_STAGING_BASE + dt_image_offset + entry[5]
        end = start + entry[6]
        if end > SBOOT_INITRD_DEST:
            raise ValueError(
                f"S-Boot staging overlap: selected hw_rev DTBH entry{index} FDT source "
                f"{start:#x}..{end:#x} must end at or below initrd destination "
                f"{SBOOT_INITRD_DEST:#x}; partition capacity alone is insufficient")
        selected.append((start, end))
    if not selected:
        raise ValueError("DTBH has no observed Exynos7880 platform/subtype hw_rev 6 entry")
    return selected


def prepare_sboot_dtbh(kernel_size, ramdisk_size, dt, page=2048):
    """Swap equal-size slots if needed; preserve every logical blob verbatim.

    Only the BOOT-embedded DTBH is repacked. No DTB property or factory DTB
    partition is changed. Unknown/multiple selected layouts fail conservatively.
    """
    entries = dtbh_entries(dt)
    try:
        validate_sboot_staging(kernel_size, ramdisk_size, dt, page)
        return dt
    except ValueError as error:
        if not str(error).startswith("S-Boot staging overlap:"):
            raise
        original_error = error
    selected = [index for index, entry in enumerate(entries) if selected_entry(entry)]
    if len(selected) != 1:
        raise ValueError("cannot safely swap multiple selected hw_rev DTBH blobs")
    chosen = selected[0]
    source = entries[chosen]
    target = min((index for index, entry in enumerate(entries) if entry[6] == source[6]),
                 key=lambda index: entries[index][5])
    if entries[target][5] >= source[5]:
        raise original_error
    output = bytearray(dt)
    other = entries[target]
    size = source[6]
    output[other[5]:other[5] + size] = dt[source[5]:source[5] + size]
    output[source[5]:source[5] + size] = dt[other[5]:other[5] + size]
    struct.pack_into("<I", output, 12 + chosen * 32 + 20, other[5])
    struct.pack_into("<I", output, 12 + target * 32 + 20, source[5])
    after = dtbh_entries(output)
    for before, current in zip(entries, after):
        if before[:5] + before[6:] != current[:5] + current[6:]:
            raise ValueError("DTBH repack changed an entry field other than offset")
        old_blob = dt[before[5]:before[5] + before[6]]
        new_blob = output[current[5]:current[5] + current[6]]
        if hashlib.sha256(old_blob).digest() != hashlib.sha256(new_blob).digest():
            raise ValueError("DTBH repack changed a logical blob or its padding")
    validate_sboot_staging(kernel_size, ramdisk_size, output, page)
    return bytes(output)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("reference_boot", type=Path)
    ap.add_argument("probe_image", type=Path)
    ap.add_argument("output_boot", type=Path)
    ap.add_argument("--ramdisk", type=Path,
                    help="replace the reference ramdisk with an XNU payload")
    args = ap.parse_args()
    if args.output_boot.exists():
        raise SystemExit("output exists; choose a new private path")
    ref = args.reference_boot.read_bytes()
    probe = args.probe_image.read_bytes()
    if ref[:8] != b"ANDROID!":
        raise SystemExit("reference is not an Android BOOT image")
    fields = struct.unpack_from("<10I", ref, 8)
    # The A720F BOOT carries os_version (0x1600015c) in the last field; the
    # copied header keeps it.
    kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr, tags_addr, page, dt_size, os_version = fields
    if page != 2048 or second_size or not ramdisk_size or not dt_size:
        raise SystemExit("unexpected Samsung BOOT layout")
    if probe[56:60] != b"ARMd" or struct.unpack_from("<Q", probe, 8)[0] != IMAGE_TEXT_OFFSET:
        raise SystemExit("Image lacks the A720F legacy header (text_offset 0x1000)")
    if struct.unpack_from("<Q", probe, 16)[0] != 0:
        raise SystemExit("probe Image has an unexpected runtime size")
    align = lambda size: (size + page - 1) // page * page
    ramdisk_off = page + align(kernel_size)
    dt_off = ramdisk_off + align(ramdisk_size)
    if dt_off + dt_size > len(ref):
        raise SystemExit("reference image is truncated")
    ramdisk = (args.ramdisk.read_bytes() if args.ramdisk else
               ref[ramdisk_off:ramdisk_off + ramdisk_size])
    if not ramdisk:
        raise SystemExit("empty ramdisk")
    dt = ref[dt_off:dt_off + dt_size]
    try:
        dt = prepare_sboot_dtbh(len(probe), len(ramdisk), dt, page)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    header = bytearray(ref[:page])
    struct.pack_into("<I", header, 8, len(probe))
    struct.pack_into("<I", header, 16, len(ramdisk))
    digest = hashlib.sha1()
    for part in (probe, ramdisk, b"", dt):
        digest.update(part)
        digest.update(struct.pack("<I", len(part)))
    header[576:596] = digest.digest()
    boot = bytearray(header)
    for part in (probe, ramdisk, dt):
        boot.extend(part)
        boot.extend(b"\0" * (align(len(part)) - len(part)))
    boot.extend(b"SEANDROIDENFORCE")
    if len(boot) >= 32 * 1024 * 1024:
        raise SystemExit("candidate exceeds the 32 MiB BOOT partition")
    args.output_boot.write_bytes(boot)
    print("candidate only; no device write")
    print("DTBH logical blobs/padding preserved; selected hw_rev staging range: " +
          ", ".join(f"{start:#x}..{end:#x}" for start, end in
                    validate_sboot_staging(len(probe), len(ramdisk), dt, page)))
    print(f"reference_sha256={hashlib.sha256(ref).hexdigest()}")
    print(f"candidate_sha256={hashlib.sha256(boot).hexdigest()}")
    print(f"bytes={len(boot)} kernel_addr={kernel_addr:#x} ramdisk_addr={ramdisk_addr:#x} tags_addr={tags_addr:#x}")


if __name__ == "__main__":
    main()
