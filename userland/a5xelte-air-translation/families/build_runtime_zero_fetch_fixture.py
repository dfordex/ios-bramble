#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Emit exact stock zero-texture fetch cases with an independent matrix oracle.

Private native code stays outside Git. This tests the actual captured2448-byte
fragment, not an authored replacement or a CPU-rendered expected framebuffer.
The oracle is derived from its optimized NIR: a half3x4 matrix multiplies fetched
RGBA, preserving alpha. Unit coefficients swap R/B, so no transcendental or
half-precision approximation is needed to predict the output.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from build_runtime_encoder import compile_runtime

ACTUAL_SHA = '0cef7b1daa3a024d50ec59b058088c2f0f90a7766030923e96e862b4903bdca1'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('mesa-build', 'registry-dir', 'publication-dir', 'output'):
        parser.add_argument('--' + option, type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    out = args.output.resolve()
    if here.parent == out or here.parent in out.parents:
        raise ValueError('private shader and payload output required')
    out.mkdir(parents=True, exist_ok=True)
    publication = args.publication_dir.resolve()
    receipt = json.loads((publication / 'receipt.json').read_text())
    reflection_path = publication / 'reflection.json'
    reflection = json.loads(reflection_path.read_text())
    code = (publication / 'stage.midgard').read_bytes()
    native = receipt['native']
    abi = receipt['native_abi']
    if (sha(publication / 'stage.midgard') != ACTUAL_SHA or
        native['sha256'] != ACTUAL_SHA or len(code) != 2448 or
        receipt['kind'] != 'dynamic-stage' or receipt['stage'] != 'fragment' or
        receipt['function'] != 'fixed_frag_lph_cph' or not receipt['stage_compiled'] or
        sha(reflection_path) != receipt['reflection']['sha256'] or
        not abi['framebuffer_fetch'] or abi['inputs'] or abi['live_textures'] or
        abi['live_ubos'] != [{'min_bytes': 72, 'native_index': 0},
                            {'min_bytes': 152, 'native_index': 2}] or
        native['tls_bytes'] or native['wls_bytes'] or
        reflection['graphics']['color_write_rules'] != [[0, 0x2222]]):
        raise ValueError('exact captured zero-texture stage or reflected ABI differs')
    (out / 'A5ZeroFetchFixtureData.inc').write_text(
        'static const uint8_t a5_zero_fetch_code[]={' +
        ','.join(str(x) for x in code) + '};\n' +
        f'#define A5_ZERO_FETCH_TAG {native["first_tag"]}\n' +
        f'#define A5_ZERO_FETCH_REGS {native["work_registers"]}\n' +
        f'#define A5_ZERO_FETCH_SHA "{ACTUAL_SHA}"\n')
    objects = []
    for source in ('runtime_misc_encode.c', 'build_runtime_zero_fetch_fixture.c'):
        obj = out / (source + '.o')
        compile_runtime(args.mesa_build.resolve(), obj, 'host', here / source,
                        (args.registry_dir.resolve(), out))
        objects.append(str(obj))
    exe = out / 'builder'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    initial = (32, 64, 96, 128)
    cases = []
    for vertex_profile, overlapping in ((603, False), (603, True), (602, False), (602, True)):
        name = 'actual_zero_fetch_' + ('color_vertex_' if vertex_profile == 602 else '') + ('same_job_overlap' if overlapping else 'full_target')
        payload = out / (name + '-payload.bin')
        expected = out / (name + '-expected.bin')
        subprocess.run([str(exe), str(payload), str(int(overlapping)), str(vertex_profile)], check=True)
        output = bytearray()
        for _y in range(32):
            for x in range(32):
                value = initial
                # Matrix columns [0,0,1], [0,1,0], [1,0,0], [0,0,0].
                # Each actual primitive set performs one destination R/B swap.
                passes = 2 if overlapping and 8 <= x < 24 else 1
                for _ in range(passes):
                    b, g, r, a = value
                    value = (r, g, b, a)
                output.extend(value)
        expected.write_bytes(output)
        data = payload.read_bytes()
        assert len(data) == 0x40000
        assert data[0x3e000:0x3f000] == bytes(initial) * 1024
        assert output != data[0x3e000:0x3f000]
        cases.append({
            'name': name, 'payload': str(payload), 'payload_sha256': sha(payload),
            'size': len(data), 'outputs': [{
                'name': 'pixels', 'offset': 0x3e000, 'bytes': 4096,
                'expected': str(expected), 'expected_sha256': sha(expected),
                'element_bytes': 1, 'tolerance': 1}],
            'immutable': [{'offset': 0x39000, 'bytes': 0x5000},
                          {'offset': 0x3f000, 'bytes': 4096}],
            'oracle': 'Actual stock fragment half3x4 matrix swaps fetched R/B; ' +
                ('overlapping rectangles x=0..23 and8..31 swap overlap twice'
                 if overlapping else 'one full-target rectangle swaps once'),
            'shader_sha256': ACTUAL_SHA,
            'request_id': receipt['request_id'], 'vertex_profile': vertex_profile})
    (out / 'manifest.json').write_text(json.dumps({
        'cases': cases,
        'reference': 'Exact2448-byte phone-verified stock AIR stage, optimized-NIR independent color-matrix oracle; no textures/samplers/FS varyings',
        'pixel_result': 'pending physical GPU execution'}, indent=2) + '\n')
    print('Prepared four actual stock zero-texture ordered-fetch GPU cases; device pixels pending')

if __name__ == '__main__':
    main()
