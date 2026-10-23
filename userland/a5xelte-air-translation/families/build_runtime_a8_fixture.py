#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual606 A8/clamped-UV GPU jobs with independent full-image pixel oracles."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from build_runtime_encoder import compile_runtime


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected(blend):
    pixels = bytearray()
    for y in range(32):
        for x in range(32):
            sx, sy = min(23, max(8, x)), min(27, max(4, y))
            alpha = (sx * 5 + sy * 7 + 13) & 255
            pixels.extend(min(255, round(alpha + d * (1 - alpha / 255)))
                          if blend else alpha for d in (32, 64, 96, 128))
    return bytes(pixels)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('registry-dir', 'mesa-build', 'output'):
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    out = a.output.resolve()
    here = Path(__file__).resolve().parent
    if here in out.parents:
        p.error('private fixture output must remain outside source')
    out.mkdir(parents=True, exist_ok=True)
    registry = a.registry_dir.resolve()
    receipt = json.loads((registry / 'compiled-registry.json').read_text())
    if sha(registry / 'A5MaliCompiledRegistryData.inc') != receipt['include_sha256']:
        raise ValueError('registry identity changed')
    objects = []
    for name in ('runtime_misc_encode', 'build_runtime_textured_fixture'):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'), (registry,))
        objects.append(str(obj))
    exe = out / 'builder'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    cases = []
    source = bytes((x * 5 + y * 7 + 13) & 255 for y in range(32) for x in range(32))
    for blend in (False, True):
        name = 'runtime606_a8_clamped_uv_' + ('source_over' if blend else 'copy')
        payload, oracle = out / (name + '.bin'), out / (name + '.expected')
        subprocess.run([str(exe), '606', str(payload)] + (['blend'] if blend else []), check=True)
        data, pixels = payload.read_bytes(), expected(blend)
        if len(data) != 0x40000 or data[0x3a000:0x3a400] != source:
            raise ValueError('actual source/row contract differs')
        initial = bytes((32, 64, 96, 128)) * 1024 if blend else bytes([0xcd]) * 4096
        if data[0x3e000:0x3f000] != initial:
            raise ValueError('CPU pre-rendered or changed output before GPU execution')
        no_clamp = bytes(v for x in source for v in (x, x, x, x))
        if pixels == no_clamp or pixels == bytes([255]) * 4096 or pixels == initial:
            raise ValueError('oracle does not distinguish missing clamp/A8 alpha sampling')
        oracle.write_bytes(pixels)
        cases.append({'name': name, 'payload': str(payload), 'payload_sha256': sha(payload),
            'outputs': [{'name': 'pixels', 'offset': 0x3e000, 'bytes': 4096,
                'element_bytes': 1, 'tolerance': 1 if blend else 0,
                'expected': str(oracle), 'expected_sha256': sha(oracle)}],
            'immutable': [{'offset': 0x39000, 'bytes': 0x5000}, {'offset': 0x3f000, 'bytes': 4096}],
            'oracle': 'A8 asymmetric bytes; UV clamp to centres x8..23/y4..27; sampled alpha replicatedRGBA' +
                      (' then premultiplied source-over destinationBGRA32/64/96/128' if blend else ''),
            'registry_include_sha256': receipt['include_sha256'],
            'runtime_source_sha256': sha(here / 'runtime_misc_encode.c'), 'runtime_verified': False})
    (out / 'manifest.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
    print(out / 'manifest.json')


if __name__ == '__main__':
    main()
