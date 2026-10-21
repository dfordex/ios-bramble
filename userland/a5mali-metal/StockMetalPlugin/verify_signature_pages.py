#!/usr/bin/env python3
"""Check local arm64 providers use valid 4 KiB CodeDirectory code slots.

codesign --verify separately validates bundle metadata and special slots.
This gate checks the granule that A5XELTE's initial header validator requires.
"""
import hashlib
from pathlib import Path
import struct
import sys


def verify(path):
    data = path.read_bytes()
    assert struct.unpack_from('<I', data)[0] == 0xFEEDFACF, 'thin Mach-O required'
    assert struct.unpack_from('<I', data, 4)[0] == 0x0100000C, 'arm64 required'
    offset = 32
    signatures = []
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        cmd, size = struct.unpack_from('<II', data, offset)
        assert size >= 8 and offset + size <= len(data), 'invalid load command'
        if cmd == 0x1D:
            start, length = struct.unpack_from('<II', data, offset + 8)
            assert start + length <= len(data), 'signature outside file'
            signatures.append(data[start:start + length])
        offset += size
    assert len(signatures) == 1, 'one LC_CODE_SIGNATURE required'
    sig = signatures[0]
    magic, length, count = struct.unpack_from('>III', sig)
    assert magic == 0xFADE0CC0 and length <= len(sig), 'invalid SuperBlob'
    checked = 0
    for index in range(count):
        _, start = struct.unpack_from('>II', sig, 12 + index * 8)
        magic, size = struct.unpack_from('>II', sig, start)
        if magic != 0xFADE0C02:
            continue
        cd = sig[start:start + size]
        hash_offset = struct.unpack_from('>I', cd, 16)[0]
        slots, limit = struct.unpack_from('>II', cd, 28)
        hash_size, hash_type, _, shift = struct.unpack_from('4B', cd, 36)
        assert shift == 12, f'CodeDirectory page shift {shift}, expected 12'
        assert hash_type == 2 and hash_size == 32, 'SHA-256 required'
        assert limit <= len(data) and slots == (limit + 4095) // 4096
        assert hash_offset + slots * hash_size <= len(cd), 'hash table truncated'
        for slot in range(slots):
            page = data[slot * 4096:min((slot + 1) * 4096, limit)]
            expected = cd[hash_offset + slot * 32:hash_offset + (slot + 1) * 32]
            assert hashlib.sha256(page).digest() == expected, f'bad code slot {slot}'
        checked += 1
        print(f'{path.name}: 4096-byte signature pages, {slots} code hashes verified')
    assert checked, 'CodeDirectory missing'


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit('usage: verify_signature_pages.py MACHO [MACHO ...]')
    for argument in sys.argv[1:]:
        verify(Path(argument))
