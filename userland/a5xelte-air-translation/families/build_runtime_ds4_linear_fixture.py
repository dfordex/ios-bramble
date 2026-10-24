#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual DS4 linear GPU fixtures with a separate integer bilinear oracle.

The runtime builder receives no expected pixels. Code is the original private
DS4 program; this script pins its released-Mesa bytes. Generation is not GPU
execution or a physical pixel result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime
from build_runtime_linear_blur_fixture import bilinear16, texel

DS4_SHA = '1771f55d5bf91525734b33166e001bdf2b402e7467988c366016c8c1f8ff2a82'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_pixels(source, linear=True):
    """AIR tap order(-,-),(+,-),(-,+),(+,+), weights1,1,2,4 over8.

    The real fractional vertex UVs map centers to(2x-.75,2y+1.25).
    Subtracting the linear half-texel center and applying +/- .5 offsets
    gives quarter coordinates(8x-7 or8x-3,8y+1 or8y+5). Bilinear values
    have denominator16; tap weights add /8, then RGB EDR=.5 adds /2.
    All half arithmetic intermediates are exact dyadic values. Final
    quantization rounds the sole .5 tie127.5 to even128. Alpha is one.
    """
    out = bytearray(4096)
    for y in range(32):
        for x in range(32):
            for c in range(3):
                samples = ((8*x-7, 8*y+1, 1), (8*x-3, 8*y+1, 1),
                           (8*x-7, 8*y+5, 2), (8*x-3, 8*y+5, 4))
                if linear:
                    n = sum(w*bilinear16(source, u, v, c) for u, v, w in samples)
                    out[(y*32+x)*4+c] = (n*255+128)//256
                else:
                    n = sum(w*texel(source, (u+2)//4, (v+2)//4, c)
                            for u, v, w in samples)
                    out[(y*32+x)*4+c] = (n*255+8)//16
            out[(y*32+x)*4+3] = 255
    return bytes(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('registry-dir', 'mesa-build', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    a = parser.parse_args()
    here = Path(__file__).resolve().parent
    out = a.output.resolve()
    if out == here or here in out.parents:
        parser.error('private output required')
    out.mkdir(parents=True, exist_ok=True)
    receipt = json.loads((a.registry_dir/'compiled-registry.json').read_text())
    if sha(a.registry_dir/'A5MaliCompiledRegistryData.inc') != receipt['include_sha256']:
        raise ValueError('registry include differs')
    profile = next(p for p in receipt['profiles'] if p['id'] == 99)
    fs = profile['passes'][0]['fragment']
    if fs['sha256'] != DS4_SHA or sha(Path(fs['path'])) != DS4_SHA:
        raise ValueError('genuine DS4 fragment required')
    objects = []
    for name in ('runtime_encode', 'build_runtime_ds4_fixture'):
        obj = out/(name+'.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here/(name+'.c'),
                        (a.registry_dir.resolve(),))
        objects.append(str(obj))
    exe = out/'builder'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    audit_object = out/'fixture-bounds.o'
    compile_runtime(a.mesa_build.resolve(), audit_object, 'host',
                    here/'test_runtime_ds4_fixture_bounds.c')
    audit = out/'fixture-bounds'
    subprocess.run(['cc', str(audit_object), '-o', str(audit)], check=True)
    cases = []
    for bits in (16, 32):
        name = f'actual_ds4_linear_indexed_u{bits}_fractional_clamp'
        payload = out/(name+'-payload.bin')
        expected = out/(name+'-expected.bin')
        subprocess.run([str(exe), str(payload), str(bits)], check=True)
        subprocess.run([str(audit), str(payload)], check=True)
        data = payload.read_bytes()
        # Reproduce the exact physical fault by restoring only the stale
        # production destination pointer in a separate negative fixture.
        import struct
        stale = bytearray(data)
        struct.pack_into('<Q', stale, 0x19a0, 0x04000000)
        stale_payload = out/(name+'-stale-preload-negative.bin')
        stale_payload.write_bytes(stale)
        rejected = subprocess.run([str(audit), str(stale_payload)], capture_output=True, text=True)
        if rejected.returncode != 1 or 'preload-destination-texture:0x4000000' not in rejected.stderr:
            raise ValueError('range audit failed to reject actual stale preload pointer')
        if len(data) != 0x40000 or data[0x4000:0x4000+3472] != Path(fs['path']).read_bytes():
            raise ValueError('DS4 shader changed')
        source = data[0x3a000:0x3e000]
        oracle = expected_pixels(source)
        different = sum(abs(a-b)>1 for a, b in zip(oracle, expected_pixels(source, False)))
        if different < 128:
            raise ValueError('fixture does not distinguish filtering')
        if data[0x3e000:0x3f000] != bytes([0xcd])*4096:
            raise ValueError('output must remain uncomputed before GPU execution')
        expected.write_bytes(oracle)
        cases.append({'name': name, 'payload': str(payload), 'payload_sha256': sha(payload),
            'size': len(data), 'outputs': [{'name': 'pixels', 'offset': 0x3e000,
            'bytes': 4096, 'expected': str(expected), 'expected_sha256': sha(expected),
            'element_bytes': 1, 'tolerance': 1}],
            'immutable': [{'offset': 0x39c00, 'bytes': 6*(bits//8)},
                          {'offset': 0x3a000, 'bytes': 0x4000}, {'offset': 0x3f000, 'bytes': 4096}],
            'profile': 99, 'fragment_sha256': DS4_SHA,
            'gpu_range_audit': 'Decoded preload/draw/FB/UBO/code/index spans fit02000000..02040000; direct SFBD load aliases zero; exact04000000 stale preload negative rejects',
            'sampler': {'min': 'linear', 'mag': 'linear', 'address': 'clamp-to-edge', 'levels': 1},
            'oracle': 'Actual DS4 ordered four weighted half taps; exact dyadic bilinear numerator/256 with RGB EDR=.5; left/bottom clamp; full4096bytes',
            'nearest_counterfactual_different_bytes_over_tolerance': different,
            'runtime_verified': False})
    (out/'manifest.json').write_text(json.dumps({'cases': cases}, indent=2)+'\n')
    print('Prepared two genuine DS4 linear cases with separate4096-byte integer pixel oracles; physical execution pending')


if __name__ == '__main__':
    main()
