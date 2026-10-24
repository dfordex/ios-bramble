#!/usr/bin/env python3
"""Synthetic staging regressions; optional private actual BOOT swap proof."""
import argparse
import importlib.util
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("a5_pack_probe", HERE / "a5xelte-pack-probe.py")
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


def dtbh(offset=0x800, size=0x1A000):
    # Generated structural metadata only; no stock DTB or private image bytes.
    data = bytearray(offset + size)
    struct.pack_into("<3I", data, 0, 0x48425444, 2, 1)
    struct.pack_into("<8I", data, 12, *packer.SBOOT_DT_ID, 3, 7, offset, size, 0x20)
    struct.pack_into(">10I", data, offset, 0xD00DFEED, 40, 40, 40, 40, 17, 16, 0, 0, 0)
    return data


class StagingTests(unittest.TestCase):
    def test_small_source_passes(self):
        ranges = packer.validate_sboot_staging(0x2860, 0x100000, dtbh())
        self.assertEqual(len(ranges), 1)
        self.assertLessEqual(ranges[0][1], packer.SBOOT_INITRD_DEST)

    def test_0215_size_rejects(self):
        with self.assertRaisesRegex(ValueError, "S-Boot staging overlap"):
            packer.validate_sboot_staging(0x2860, 0x1DD19F0, dtbh(0x34800))

    def test_0214_tail_is_conservatively_rejected(self):
        with self.assertRaisesRegex(ValueError, "S-Boot staging overlap"):
            packer.validate_sboot_staging(0x2860, 0x1DB0850, dtbh(0x34800))

    def test_table_and_data_bounds_reject(self):
        for offset, size in ((16, 0x1A000), (0x800, 0x1A001), (0xFFFFFFFF, 40)):
            data = dtbh()
            struct.pack_into("<2I", data, 12 + 20, offset, size)
            with self.subTest(offset=offset, size=size), self.assertRaisesRegex(ValueError, "offset/size"):
                packer.validate_sboot_staging(0x2860, 0x100000, data)

    def test_fdt_header_bounds_reject(self):
        for magic, total in ((0, 40), (0xD00DFEED, 39), (0xD00DFEED, 0x1A001)):
            data = dtbh()
            struct.pack_into(">2I", data, 0x800, magic, total)
            with self.subTest(magic=magic, total=total), self.assertRaisesRegex(ValueError, "FDT magic/total"):
                packer.validate_sboot_staging(0x2860, 0x100000, data)

    def test_every_matching_entry_checked(self):
        data = dtbh(0x34800)
        struct.pack_into("<I", data, 8, 2)
        data[44:76] = data[12:44]
        struct.pack_into("<I", data, 12 + 20, 0x800)
        struct.pack_into(">2I", data, 0x800, 0xD00DFEED, 40)
        with self.assertRaisesRegex(ValueError, "entry1 FDT source"):
            packer.validate_sboot_staging(0x2860, 0x1DD19F0, data)

    def test_equal_size_swap_preserves_logical_blobs(self):
        data = dtbh(0x34800)
        struct.pack_into("<I", data, 8, 2)
        struct.pack_into("<8I", data, 44, *packer.SBOOT_DT_ID, 1, 1, 0x800, 0x1A000, 0x20)
        data[0x800:0x1A800] = bytes([0x31]) * 0x1A000
        struct.pack_into(">2I", data, 0x800, 0xD00DFEED, 40)
        reordered = packer.prepare_sboot_dtbh(0x2860, 0x1DD19F0, data)
        self.assertEqual(packer.validate_sboot_staging(0x2860, 0x1DD19F0, reordered),
                         [(0x41FDA800, 0x41FF4800)])
        for old, new in zip(packer.dtbh_entries(data), packer.dtbh_entries(reordered)):
            self.assertEqual(old[:5] + old[6:], new[:5] + new[6:])
            self.assertEqual(data[old[5]:old[5]+old[6]], reordered[new[5]:new[5]+new[6]])

    def test_no_safe_equal_size_slot_rejects(self):
        with self.assertRaisesRegex(ValueError, "S-Boot staging overlap"):
            packer.prepare_sboot_dtbh(0x2860, 0x1DD19F0, dtbh(0x34800))

    def test_overlapping_blob_ranges_reject(self):
        data = dtbh()
        struct.pack_into("<I", data, 8, 2)
        data[44:76] = data[12:44]
        with self.assertRaisesRegex(ValueError, "overlapping DTBH blob ranges"):
            packer.prepare_sboot_dtbh(0x2860, 0x100000, data)

    def test_small_cli_writes_candidate(self):
        with tempfile.TemporaryDirectory(prefix="a5-pack-small-") as temp:
            folder = Path(temp)
            probe = bytearray(64)
            struct.pack_into("<Q", probe, 8, 0x205000)
            probe[56:60] = b"ARMd"
            tree = dtbh(size=40)
            header = bytearray(2048)
            header[:8] = b"ANDROID!"
            struct.pack_into("<10I", header, 8, len(probe), 0x10008000, 1,
                             0x11000000, 0, 0x10F00000, 0x10000100, 2048, len(tree), 0)
            reference = folder / "reference.img"
            reference.write_bytes(header + probe + bytes(2048-len(probe)) + b"x" + bytes(2047) + tree)
            image = folder / "Image"
            image.write_bytes(probe)
            output = folder / "candidate.img"
            result = subprocess.run([sys.executable, str(HERE / "a5xelte-pack-probe.py"),
                                     str(reference), str(image), str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.is_file())


def actual_roundtrip(path, proof_path=None):
    raw = path.read_bytes()
    kernel_size, _, ramdisk_size, _, _, _, _, page, dt_size, _ = struct.unpack_from("<10I", raw, 8)
    align = lambda size: (size + page - 1) // page * page
    ramdisk_offset = page + align(kernel_size)
    dt_offset = ramdisk_offset + align(ramdisk_size)
    original_dt = raw[dt_offset:dt_offset+dt_size]
    try:
        packer.validate_sboot_staging(kernel_size, ramdisk_size, original_dt, page)
    except ValueError as error:
        if "S-Boot staging overlap" not in str(error):
            raise
        before_failure = str(error)
    else:
        raise AssertionError("actual oversized staging image unexpectedly passed the original guard")
    with tempfile.TemporaryDirectory(prefix="a5-pack-actual-") as temp:
        folder = Path(temp)
        image = folder / "Image"
        image.write_bytes(raw[page:page + kernel_size])
        output = folder / "reordered.img"
        result = subprocess.run([sys.executable, str(HERE / "a5xelte-pack-probe.py"),
                                 str(path), str(image), str(output)], capture_output=True, text=True)
        if result.returncode or not output.exists():
            raise AssertionError(f"actual same-size repack failed: {result.stderr}")
        after = output.read_bytes()
        new_dt = after[dt_offset:dt_offset+dt_size]
        if len(raw) != len(after) or raw[page:dt_offset] != after[page:dt_offset]:
            raise AssertionError("repack changed loader/payload bytes or BOOT size")
        if raw[:576] + raw[596:page] != after[:576] + after[596:page]:
            raise AssertionError("repack changed a BOOT header field other than its digest")
        logical = []
        for index, (old, new) in enumerate(zip(packer.dtbh_entries(original_dt), packer.dtbh_entries(new_dt))):
            if old[:5] + old[6:] != new[:5] + new[6:]:
                raise AssertionError("entry metadata changed outside offsets")
            old_sha = hashlib.sha256(original_dt[old[5]:old[5]+old[6]]).hexdigest()
            new_sha = hashlib.sha256(new_dt[new[5]:new[5]+new[6]]).hexdigest()
            if old_sha != new_sha:
                raise AssertionError("logical blob or padding changed")
            logical.append(dict(entry=index, before_offset=hex(old[5]), after_offset=hex(new[5]),
                                bytes=old[6], sha256=old_sha))
        ranges = packer.validate_sboot_staging(kernel_size, ramdisk_size, new_dt, page)
        proof = dict(before_failure=before_failure, after_ranges=[[hex(a), hex(b)] for a,b in ranges],
                     boot_bytes=len(after), boot_sha256=hashlib.sha256(after).hexdigest(),
                     loader_and_payload_unchanged=True, logical_blobs=logical,
                     claim="Host packing/memory-layout proof; physical S-Boot execution remains pending")
        if proof_path:
            proof_path.write_text(json.dumps(proof, indent=2) + "\n")
        print("PASS actual original rejected, repack passes strict staging guard;",
              len(logical), "logical blobs/padding hashes equal; loader/payload unchanged")
        print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual-boot", type=Path)
    parser.add_argument("--proof", type=Path)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(StagingTests)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)
    if args.actual_boot:
        actual_roundtrip(args.actual_boot, args.proof)
