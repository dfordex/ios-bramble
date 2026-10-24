#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual602 source-over fixture with independent premultiplied pixel oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('mesa-build', 'registry-dir', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    out = args.output.resolve()
    if here == out or here in out.parents:
        raise ValueError('native shader payload output must remain private')
    out.mkdir(parents=True, exist_ok=True)
    objects = []
    for source in ('runtime_misc_encode.c', 'build_runtime_602_blend_fixture.c'):
        obj = out / (source + '.o')
        compile_runtime(args.mesa_build.resolve(), obj, 'host', here / source,
                        (args.registry_dir.resolve(),))
        objects.append(str(obj))
    builder = out / 'builder'
    subprocess.run(['cc', *objects, '-o', str(builder)], check=True)
    payload = out / 'actual602_source_over-payload.bin'
    expected = out / 'actual602_source_over-expected.bin'
    subprocess.run([str(builder), str(payload)], check=True)
    initial = (32, 64, 96, 128)
    result = bytearray()
    for y in range(32):
        for x in range(32):
            value = initial
            if 4 <= x < 28 and 4 <= y < 28:
                alpha = .25 if x < 16 else .75
                # Exact half input is premultiplied linear RGBA (.5,.25,.75,1)*a.
                # Renderer writes BGRA UNORM: source + destination*(1-source.a).
                src = (.75 * alpha, .25 * alpha, .5 * alpha, alpha)
                value = tuple(round(s * 255 + d * (1-alpha)) for s, d in zip(src, initial))
            result.extend(value)
    expected.write_bytes(result)
    data = payload.read_bytes()
    assert len(data) == 0x40000 and data[0x3e000:0x3f000] == bytes(initial) * 1024
    case = {'name': 'actual602_source_over', 'payload': str(payload),
            'payload_sha256': sha(payload), 'size': len(data), 'outputs': [{
                'name': 'pixels', 'offset': 0x3e000, 'bytes': 4096,
                'expected': str(expected), 'expected_sha256': sha(expected),
                'element_bytes': 1, 'tolerance': 1}],
            'immutable': [{'offset': 0x39000, 'bytes': 0x5000},
                          {'offset': 0x3f000, 'bytes': 4096}],
            'oracle': 'premultiplied source-over, two exact half alpha values, nonzero BGRA destination, scissor border unchanged'}
    (out / 'manifest.json').write_text(json.dumps({'schema': 1, 'cases': [case]}, indent=2) + '\n')
    print(out / 'manifest.json')

if __name__ == '__main__':
    main()
