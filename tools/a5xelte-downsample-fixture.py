#!/usr/bin/env python3
"""Embed a validated private downsample4 descriptor in the local XNU tree.

Shader bytes come from the user's staged QuartzCore metallib and must never
be committed. The source-only CPU oracle is shared with the host builder.
"""
import argparse
import hashlib
from pathlib import Path
import struct


EXPECTED_SHA256 = '7683f29de37719b5aaa7e1716df25e1aebe52f9930d57f79d8ce792b62f74d24'
EXPECTED_SIZE = 0x4000
BASE = 0x02000000


def validate(data):
    if len(data) != EXPECTED_SIZE or hashlib.sha256(data).hexdigest() != EXPECTED_SHA256:
        raise ValueError('downsample4 descriptor size or SHA256 mismatch')
    for offset, expected in {
        0x18: BASE + 0x100, 0xb0: BASE + 0x300,
        0x1b0: BASE + 0x300, 0x350: BASE + 0x8000,
        0x380: BASE + 0x8000, 0x620: BASE + 0x4000,
        0x660: BASE + 0x600, 0x3d8: BASE + 0x9000,
        0x3e0: BASE + 0xa000,
    }.items():
        if struct.unpack_from('<Q', data, offset)[0] != expected:
            raise ValueError(f'downsample4 pointer mismatch at 0x{offset:x}')
    for offset, expected in ((0x10, 0x0b), (0x110, 0x0f), (0x210, 0x13)):
        if data[offset] != expected:
            raise ValueError(f'downsample4 job type mismatch at 0x{offset:x}')
    if struct.unpack_from('<II', data, 0x220) != (0, 0x00010001):
        raise ValueError('downsample4 fragment bounds must cover tiles 0..1 on both axes')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('descriptor', type=Path)
    ap.add_argument('output_include', type=Path)
    args = ap.parse_args()
    data = args.descriptor.read_bytes()
    try:
        validate(data)
    except ValueError as error:
        ap.error(str(error))
    reference = (Path(__file__).resolve().parent.parent / 'userland' /
                 'a5xelte-air-translation' / 'downsample_reference.h').read_text()
    words = struct.unpack('<4096I', data)
    lines = ['/* Generated locally from private Apple-derived shaders; never commit. */',
             reference, 'static const uint32_t kA5DownsampleFixture[4096] = {']
    for i in range(0, len(words), 8):
        lines.append('    ' + ', '.join(f'0x{word:08x}u' for word in words[i:i + 8]) + ',')
    lines.append('};')
    args.output_include.write_text('\n'.join(lines) + '\n')
    print(f'wrote {args.output_include}; descriptor SHA256={EXPECTED_SHA256}')


if __name__ == '__main__':
    main()
