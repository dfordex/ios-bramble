#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read-only shader coverage audit for the locally supplied iOS 16.7.16 QC.

Models the audited warmup path with no supported feature sets and no native
pipeline library. Emits names/metadata only; does not extract executable bytes,
create shader objects, or assert that the identified shaders are implemented.
"""
import argparse
import json
from pathlib import Path
import struct
import uuid


EXPECTED_UUID = "9e40b2eb-260c-3af1-ae45-a1a551a8c1b9"


class Image:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        if len(self.data) < 32 or self.u32(0) != 0xFEEDFACF:
            raise ValueError("expected an extracted 64-bit Mach-O image")
        commands = self.u32(16)
        commands_end = 32 + self.u32(20)
        if commands > 256 or commands_end > len(self.data):
            raise ValueError("invalid Mach-O load commands")
        self.segments = []
        image_uuid = None
        offset = 32
        for _ in range(commands):
            command, size = struct.unpack_from("<II", self.data, offset)
            if size < 8 or offset + size > commands_end:
                raise ValueError("invalid load command bounds")
            if command == 0x19:
                if size < 72:
                    raise ValueError("short segment command")
                address, _, file_offset, file_size = struct.unpack_from(
                    "<QQQQ", self.data, offset + 24)
                if file_offset + file_size > len(self.data):
                    raise ValueError("segment exceeds image")
                self.segments.append((address, file_size, file_offset))
            elif command == 0x1B:
                if size != 24:
                    raise ValueError("invalid UUID command")
                image_uuid = str(uuid.UUID(bytes=self.data[offset + 8:offset + 24]))
            offset += size
        if image_uuid != EXPECTED_UUID:
            raise ValueError("unreviewed QuartzCore UUID; fixed tables must be reaudited")

    def u32(self, offset):
        return struct.unpack_from("<I", self.data, offset)[0]

    def offset(self, address, size=1):
        # The extracted cache retains slide-chain tags in the high pointer bits.
        address &= 0xFFFFFFFFF
        for start, length, file_offset in self.segments:
            if start <= address and address + size <= start + length:
                return file_offset + address - start
        raise ValueError(f"unmapped address or range: {address:#x}+{size:#x}")

    def pointer(self, address):
        return struct.unpack_from("<Q", self.data, self.offset(address, 8))[0] & 0xFFFFFFFFF

    def string(self, address):
        offset = self.offset(address)
        end = self.data.find(b"\0", offset, min(offset + 257, len(self.data)))
        if end < 0:
            raise ValueError("unbounded string")
        self.offset(address, end - offset + 1)
        return self.data[offset:end].decode("ascii")

    def cfstring(self, address):
        if not address:
            return None
        return self.string(self.pointer(address + 16))


def audit(image):
    texture_codes = {
        image.string(image.pointer(0x1D5B45F18 + index * 8)): index
        for index in range(90)
    }
    rows = []
    skipped = {"required_feature_set": 0, "generic_without_native_library": 0,
               "no_fast_shader": 0}
    for index in range(1079):
        address = 0x1D5B3B350 + index * 40
        _, requires_feature, _, _, _ = struct.unpack_from(
            "<QQQQQ", image.data, image.offset(address, 40))
        name = image.string(image.pointer(address))
        if requires_feature:
            skipped["required_feature_set"] += 1
            continue
        parts = name.split("_")
        if len(parts) < 2:
            raise ValueError("invalid pipeline name shape")
        fragment = parts[1]
        flags = fragment.split("X", 1)[1] if "X" in fragment else ""
        if "g" in flags:
            skipped["generic_without_native_library"] += 1
            continue
        texture = 0
        if "T" in fragment:
            token = fragment.split("T", 1)[1][:3]
            if token in texture_codes:
                texture = texture_codes[token]
            elif len(token) == 3 and token.isdigit():
                texture = int(token)
            else:
                raise ValueError(f"unknown texture token: {token}")
        if texture >= 128:
            raise ValueError("texture config index outside audited table")
        config = image.data[image.offset(0x188564D4C + texture * 7)] & 63
        if not config:
            skipped["no_fast_shader"] += 1
            continue
        if config >= 49:
            raise ValueError("fast shader index outside audited table")
        fragment_name = image.cfstring(image.pointer(0x1D5B45C08 + config * 16))
        vertex_layout = image.data[image.offset(0x1D5B45C10 + config * 16)] & 31
        if vertex_layout >= 18:
            raise ValueError("vertex layout outside audited table")
        vertex_name = image.cfstring(image.pointer(0x1D5B48058 + vertex_layout * 24))
        if not fragment_name or not vertex_name:
            raise ValueError("fast shader entry has no direct function name")
        suffix = "_lph" if "h" in flags else "_lpf"
        rows.append({"row": index, "pipeline": name, "texture_index": texture,
                     "fast_shader_index": config,
                     "vertex": vertex_name + suffix,
                     "fragment": fragment_name + suffix,
                     "constant_values": None})
    return {"quartzcore_uuid": EXPECTED_UUID,
            "profile": "no feature sets; no native pipeline library; normal precompiled lookup branch",
            "evidence": "static table order; async execution order is not guaranteed",
            "input_rows": 1079, "skipped": skipped,
            "first_dispatched_fast_profile": rows[0] if rows else None,
            "direct_fast_profiles": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("quartzcore", help="locally extracted stock QuartzCore Mach-O")
    args = parser.parse_args()
    try:
        print(json.dumps(audit(Image(args.quartzcore)), indent=2))
    except (ValueError, struct.error, UnicodeError, OSError) as error:
        parser.exit(1, f"coverage audit failed: {error}\n")


if __name__ == "__main__":
    main()
