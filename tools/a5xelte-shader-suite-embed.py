#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate private shader fixtures and embed bounded GPU-only tests in XNU.

Only generated payloads/expected pixels go to the local include, never Git.
The sparse codec preserves all bytes and compresses zero/fill regions without
a kernel decompressor or additional allocation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

SIZE = 0x40000
BASE = 0x02000000


def fnv(data):
    value = 0xcbf29ce484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    return value


def authenticate(data, pin):
    if not isinstance(pin, str) or hashlib.sha256(data).hexdigest() != pin:
        raise ValueError('missing or mismatched artifact digest')


def sparse(data):
    out = bytearray()
    pos = 0
    while pos < len(data):
        if not data[pos]:
            pos += 1
            continue
        run = pos + 1
        while run < len(data) and data[run] == data[pos]:
            run += 1
        if run - pos >= 16:
            out += struct.pack('<II', pos, (run - pos) | 0x80000000) + data[pos:pos+1]
            pos = run
            continue
        start = pos
        pos += 1
        while pos < len(data):
            run = pos + 1
            while run < len(data) and data[run] == data[pos] and run - pos < 16:
                run += 1
            if run - pos >= 16:
                break
            pos += 1
        out += struct.pack('<II', start, pos - start) + data[start:pos]
    if len(out) > 0x48000:
        raise ValueError('encoded payload exceeds kernel bound')
    return bytes(out)


def unpack(encoded):
    out = bytearray(SIZE)
    cursor = end = 0
    while cursor < len(encoded):
        if len(encoded) - cursor < 8:
            raise ValueError('short sparse header')
        off, length = struct.unpack_from('<II', encoded, cursor)
        cursor += 8
        fill, length = bool(length & 0x80000000), length & 0x7fffffff
        n = 1 if fill else length
        if not length or off < end or off + length > SIZE or n > len(encoded) - cursor:
            raise ValueError('invalid sparse range')
        out[off:off+length] = encoded[cursor:cursor+1] * length if fill else encoded[cursor:cursor+n]
        cursor += n
        end = off + length
    return bytes(out)


def identifier(name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,100}', name):
        raise ValueError('fixture name must be a bounded ASCII identifier')
    return name


def array(name, data):
    if not data:
        raise ValueError('zero-length array')
    lines = [f'static const uint8_t {name}[] = {{']
    lines += ['    ' + ','.join(f'0x{v:02x}' for v in data[i:i+24]) + ',' for i in range(0, len(data), 24)]
    return '\n'.join(lines + ['};'])


def region(offset, length):
    if not isinstance(offset, int) or not isinstance(length, int) or offset < 0 or length <= 0 or offset + length > SIZE:
        raise ValueError('region outside pinned private data window')


def valid_job_chain(payload):
    def word(off): return struct.unpack_from('<I', payload, off)[0]
    def pointer(off): return struct.unpack_from('<Q', payload, off)[0]
    def header(off, typ, nxt):
        return (not word(off) and not word(off+4) and not pointer(off+8)
                and word(off+16)&1 and ((word(off+16)>>1)&127)==typ
                and pointer(off+24)==nxt)
    if not header(0x100,7,0) or not header(0x200,9,0):
        return False
    if header(0,5,BASE+0x100):
        return True
    return (header(0,5,BASE+0x1800) and header(0x1800,7,BASE+0x100)
            and word(0x10)>>16==1 and word(0x1810)>>16==2
            and word(0x110)>>16==3 and word(0x14)==0
            and word(0x1814)==1 and word(0x114)==(1|(2<<16)))


def embed(manifests, output):
    lines = ['/* Generated private Mac shader fixtures; do not commit. */']
    records, names, evidence = [], set(), []
    for manifest in manifests:
        for case in json.loads(manifest.read_text())['cases']:
            name = identifier(case['name'])
            if name in names:
                raise ValueError('duplicate fixture name')
            names.add(name)
            payload = Path(case['payload']).read_bytes()
            authenticate(payload, case.get('payload_sha256'))
            if len(payload) != SIZE:
                raise ValueError(f'{name}: payload is not exactly 256KiB')
            if any(payload[off] != typ for off, typ in ((0x10, 0xb), (0x110, 0xf), (0x210, 0x13))):
                raise ValueError(f'{name}: wrong vertex/tiler/fragment header')
            if not valid_job_chain(payload):
                raise ValueError(f'{name}: invalid vertex/preload/tiler/fragment chain')
            encoded = sparse(payload)
            if unpack(encoded) != payload:
                raise ValueError('sparse codec changed data')
            prefix = 'a5suite_' + name
            lines.append(array(prefix + '_payload', encoded))
            outputs = []
            if not 1 <= len(case['outputs']) <= 8:
                raise ValueError('unsupported output count')
            for i, out in enumerate(case['outputs']):
                region(out['offset'], out['bytes'])
                width = out['element_bytes']
                tolerance = out.get('tolerance', 0)
                if width not in (1, 2, 4) or out['bytes'] % width or not 0 <= tolerance <= 255:
                    raise ValueError('invalid comparison contract')
                expected = Path(out['expected']).read_bytes()
                authenticate(expected, out.get('expected_sha256', case.get('expected_sha256') if len(case['outputs']) == 1 else None))
                if len(expected) != out['bytes']:
                    raise ValueError('expected output size differs')
                symbol = prefix + f'_expected_{i}'
                lines.append(array(symbol, expected))
                mask_symbol = 'nullptr'
                if out.get('mask'):
                    mask = Path(out['mask']).read_bytes()
                    authenticate(mask, out.get('mask_sha256'))
                    if len(mask) != len(expected) or tolerance:
                        raise ValueError('mask length or tolerance differs')
                    mask_symbol = prefix + f'_mask_{i}'
                    lines.append(array(mask_symbol, mask))
                outputs.append('{'+f'{json.dumps(identifier(out["name"]))},{out["offset"]},{out["bytes"]},{width},{tolerance},{symbol},{mask_symbol}'+'}')
            lines.append(f'static const A5SuiteOutput {prefix}_outputs[] = {{'+','.join(outputs)+'};')
            imm = case.get('immutable', [])
            if not imm or len(imm) > 16:
                raise ValueError('source/guard checks are mandatory and bounded')
            for r in imm:
                region(r['offset'], r['bytes'])
                if any(r['offset'] < o['offset'] + o['bytes'] and o['offset'] < r['offset'] + r['bytes'] for o in case['outputs']):
                    raise ValueError('immutable/output overlap')
            lines.append(f'static const A5SuiteRegion {prefix}_immutable[] = {{'+','.join('{'+f'{r["offset"]},{r["bytes"]}'+'}' for r in imm)+'};')
            records.append('{'+f'{json.dumps(name)},{prefix}_payload,sizeof({prefix}_payload),0x{fnv(payload):016x}ULL,{prefix}_outputs,{len(outputs)},{prefix}_immutable,{len(imm)}'+'}')
            evidence.append({'name': name, 'payload_sha256': hashlib.sha256(payload).hexdigest(), 'encoded_bytes': len(encoded), 'outputs': case['outputs'], 'immutable': imm})
    if not 1 <= len(records) <= 64:
        raise ValueError('suite case count out of bounds')
    lines.append('static const A5SuiteCase kA5SuiteCases[] = {'+','.join(records)+'};')
    output.write_text('\n'.join(lines)+'\n')
    return evidence


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest', type=Path, action='append', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--evidence', type=Path, required=True)
    a = p.parse_args()
    evidence = embed(a.manifest, a.output)
    a.evidence.write_text(json.dumps({'cases': evidence}, indent=2)+'\n')
    print(f'embedded {len(evidence)} actual Mac shader test cases')


if __name__ == '__main__':
    main()
