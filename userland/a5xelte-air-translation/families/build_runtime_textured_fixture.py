#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Two actual runtime604/605 GPU pixel oracles; no proprietary bytes in source."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from build_runtime_encoder import compile_runtime


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected(profile):
    result = bytearray()
    for y in range(32):
        for x in range(32):
            r, g = (255 if (x // 7) & 1 else 0), (255 if (y // 5) & 1 else 0)
            if profile == 604:
                b = 255 if (x // 11 + y // 3) & 1 else 0
                # Metal half4 colour (.5,.25,1,.5), applied to sampled RGBA;
                # final texture/pixel layout is BGRA. Tolerance1 allows only
                # the single final UNORM rounding choice at half values.
                result.extend((b, round(g * .25), round(r * .5), 128))
            else:
                result.extend((r, r, r, g))
    return bytes(result)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('registry-dir', 'mesa-build', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent
    registry = a.registry_dir.resolve()
    receipt = json.loads((registry / 'compiled-registry.json').read_text())
    if sha(registry / 'A5MaliCompiledRegistryData.inc') != receipt['include_sha256']:
        raise ValueError('authenticated compiled registry changed')
    objects = []
    for name in ('runtime_misc_encode', 'build_runtime_textured_fixture'):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'), (registry,))
        objects.append(str(obj))
    exe = out / 'builder'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    cases = []
    for profile in (604, 605):
        payload, oracle = out / f'{profile}-payload.bin', out / f'{profile}-expected.bin'
        subprocess.run([str(exe), str(profile), str(payload)], check=True)
        data = payload.read_bytes()
        if len(data) != 0x40000 or data[0x3e000:0x3f000] != bytes([0xcd]) * 4096:
            raise ValueError('fixture output must be fully poisoned, not CPU-rendered')
        reference = expected(profile)
        oracle.write_bytes(reference)
        # Independently verify the complete source against its documented
        # layout. A BGRA-vs-RG or R/B swap is not allowed to change the oracle.
        source = bytearray()
        for y in range(32):
            for x in range(32):
                r, g = (255 if (x // 7) & 1 else 0), (255 if (y // 5) & 1 else 0)
                source.extend((255 if (x // 11 + y // 3) & 1 else 0, g, r, 255) if profile == 604 else (r, g))
        if data[0x3a000:0x3a000 + len(source)] != source:
            raise ValueError('fixture source does not follow independent colour/row contract')
        # These should catch exactly the distinct new semantic gaps, not pass
        # with an accidentally reused603 shader or ignored604 colour varying.
        wrong = source if profile == 604 else bytes(v for i in range(0, len(source), 2)
            for v in (0, source[i + 1], source[i], 255))
        if sum(abs(a - b) > 1 for a, b in zip(reference, wrong)) < 1024:
            raise ValueError('oracle does not distinguish the prior603 shader')
        cases.append({
            'name': 'runtime604_texture_times_halfcolour' if profile == 604 else 'runtime605_rg8_luma_alpha',
            'payload': str(payload), 'payload_sha256': sha(payload), 'size': len(data),
            'outputs': [{'name': 'pixels', 'offset': 0x3e000, 'bytes': 4096,
                'expected': str(oracle), 'expected_sha256': sha(oracle), 'element_bytes': 1,
                'tolerance': 1 if profile == 604 else 0}],
            'immutable': [{'offset': 0x39000, 'bytes': 0x5000}, {'offset': 0x3f000, 'bytes': 4096}],
            'registry_include_sha256': receipt['include_sha256'],
            'runtime_source_sha256': sha(here / 'runtime_misc_encode.c'),
            'oracle': 'Independent BGRA source times constant half4(.5,.25,1,.5)' if profile == 604 else
                'Independent RG8 source: BGRA output=(R,R,R,G), normalized nearest pixel-centre UV',
            'source_format_contract': 'Metal80 BGRA8' if profile == 604 else
                'Metal30 RG8; released Mesa26.2.4 pan_format.c R8G8_UNORM→RG8_UNORM/RG01; no claim actual iOS source format',
            'runtime_verified': False,
        })
    (out / 'manifest.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
    print(out / 'manifest.json')


if __name__ == '__main__':
    main()
