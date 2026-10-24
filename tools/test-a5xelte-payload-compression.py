#!/usr/bin/env python3
"""Test the actual payload compressor on patterns and a real generated installer."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import textwrap
import time
import zlib

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--payload', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
source = Path(__file__).with_name('a5xelte-metal-bundle-embed.py').read_text()
start = source.index('        packed = data\n', source.index('    packed_sizes = []'))
end = source.index('        compressed = ', start)
namespace = {'zlib': zlib}
exec('def pack(data, extended=True):\n' + textwrap.indent(textwrap.dedent(source[start:end]), '    ') + '    return packed\n', namespace)
pack = namespace['pack']

def check(data):
    old = zlib.compress(data, 9)
    new = pack(data)
    assert len(new) <= len(old)
    decoded = zlib.decompress(new)
    assert decoded == data and zlib.crc32(decoded) == zlib.crc32(data)
    assert pack(data, False) == data
    # The actual uncompressed fallback remains strictly smaller than either
    # compression stream for empty or incompressible files.
    chosen = new if len(new) < len(data) else data
    assert len(chosen) <= min(len(old), len(data))
    return len(old), len(new), len(chosen)

rng = random.Random(0xA523)
for n in (0, 1, 2, 15, 16, 255, 256, 4095, 4096, 16384, 65536):
    for data in (bytes(n), bytes((i & 255) for i in range(n)), rng.randbytes(n)):
        check(data)
text = a.payload.read_text()
metadata = {}
for name, index, raw, packed in re.findall(r'\{ "([^"\n]+)", a5metal_payload_(\d+), (\d+)U, 0[0-7]+, (\d+)U, \d+U, \d+U \}', text):
    metadata[int(index)] = (name, int(raw), int(packed))
rows = []
started = time.monotonic()
for match in re.finditer(r'static const unsigned char a5metal_payload_(\d+)\[\] = \{(.*?)\n\};', text, re.S):
    index = int(match[1])
    name, raw_size, packed_size = metadata[index]
    body = re.sub(r'/\*.*?\*/', '', match[2], flags=re.S)
    encoded = bytes.fromhex(body.replace('0x', '').replace(',', ' '))
    data = zlib.decompress(encoded) if packed_size else encoded[:raw_size]
    assert len(data) == raw_size
    old, new, chosen = check(data)
    assert min(old, len(data)) == len(encoded) or not data
    rows.append({'path': name, 'raw_bytes': len(data), 'old_bytes': min(old, len(data)), 'new_bytes': chosen, 'saved_bytes': min(old, len(data)) - chosen, 'raw_sha256': hashlib.sha256(data).hexdigest(), 'raw_crc32': f'{zlib.crc32(data):08x}'})
assert len(rows) == len(metadata) > 0
result = {'files': rows, 'file_count': len(rows), 'pattern_cases': 33, 'old_packed_bytes': sum(x['old_bytes'] for x in rows), 'new_packed_bytes': sum(x['new_bytes'] for x in rows), 'saved_bytes': sum(x['saved_bytes'] for x in rows), 'roundtrip_and_crc_identical': True, 'never_larger': True, 'elapsed_seconds': time.monotonic() - started, 'zlib_version': zlib.ZLIB_VERSION, 'input_payload_sha256': hashlib.sha256(a.payload.read_bytes()).hexdigest(), 'source_sha256': hashlib.sha256(source.encode()).hexdigest()}
(a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k:v for k,v in result.items() if k != 'files'}, indent=2))
print('Largest reductions:')
for row in sorted(rows, key=lambda x:x['saved_bytes'], reverse=True)[:8]:
    print(row['saved_bytes'], row['path'])
