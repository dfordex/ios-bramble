#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Genuine indexed linear blur fixtures with an independent bilinear oracle.

Actual private shaders/source are supplied by the checked registry/legacy
manifest. Oracle pixels never enter descriptor/input generation. This prepares
physical GPU tests; compiling or generating them is not a GPU execution result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
from build_runtime_encoder import compile_runtime


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def texel(source, x, y, channel):
    x = max(0, min(63, x))
    y = max(0, min(63, y))
    value = source[(y * 64 + x) * 4 + channel]
    if value not in (0, 255):
        raise ValueError('oracle requires the authenticated binary source')
    return value // 255


def bilinear16(source, x4, y4, channel):
    """Exact normalized-linear sampling: texel-center coordinates in quarters.

    Return the numerator over16. Clamp each neighbor, including both sides of
    a boundary, independently. Fractional weights are exact dyadic values.
    """
    x, fx = divmod(x4, 4)
    y, fy = divmod(y4, 4)
    return sum(texel(source, x + dx, y + dy, channel) * wx * wy
               for dx, wx in ((0, 4 - fx), (1, fx))
               for dy, wy in ((0, 4 - fy), (1, fy)))


def expected_pixels(source, linear=True):
    """Profile100's actual16 equal taps followed by RGB EDR=.5.

    UV vertices(-1.75,.25)..(62.25,64.25) map pixel centers into source
    coordinates(2*x-.75,2*y+1.25). Hardware linear centers subtract.5.
    Authenticated offsets are +/- .5 and +/-1.5 source texels. Every sample
    and half arithmetic intermediate is an exact multiple of1/256 or coarser;
    final RGB scale gives1/512. Alpha is one. UNORM8 nearest-even has only
    the maximum127.5 tie here, which rounds to128.
    """
    out = bytearray(4096)
    for y in range(32):
        for x in range(32):
            for c in range(3):
                coords = ((8*x - 5 + dx, 8*y + 3 + dy)
                          for dx in (-6, -2, 2, 6) for dy in (-6, -2, 2, 6))
                if linear:
                    numerator = sum(bilinear16(source, u, v, c) for u, v in coords)
                    out[(y*32+x)*4+c] = (numerator*255+256)//512
                else:
                    # Nearest normalized sampling uses floor(textureUV*size),
                    # without the linear sampler's half-texel center shift.
                    numerator = sum(texel(source, (u+2)//4, (v+2)//4, c)
                                    for u, v in coords)
                    out[(y*32+x)*4+c] = (numerator*255+16)//32
            out[(y*32+x)*4+3] = 255
    return bytes(out)


def validate_inputs(legacy):
    expected_offsets = ((.5/64, .5/64), (1.5/64, .5/64),
                        (.5/64, 1.5/64), (1.5/64, 1.5/64))
    if struct.unpack_from('<8f', legacy, 0xa80) != tuple(v for p in expected_offsets for v in p):
        raise ValueError('downsample8 actual sixteen-tap contract changed')
    if struct.unpack_from('<e', legacy, 0xb00) != (.5,):
        raise ValueError('EDR contract changed')
    if struct.unpack_from('<4f', legacy, 0xa40) != (1/64, 1/64, 0, 0):
        raise ValueError('texture transform contract changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('registry-dir', 'legacy-manifest', 'mesa-build', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    a = parser.parse_args()
    here = Path(__file__).resolve().parent
    out = a.output.resolve()
    if here in out.parents or out == here:
        parser.error('private fixture output required')
    out.mkdir(parents=True, exist_ok=True)
    receipt = json.loads((a.registry_dir/'compiled-registry.json').read_text())
    if sha(a.registry_dir/'A5MaliCompiledRegistryData.inc') != receipt['include_sha256']:
        raise ValueError('registry receipt differs')
    case = next(c for c in json.loads(a.legacy_manifest.read_text())['cases']
                if c['name'] == 'downsample_8_frag_lph_bgra8')
    legacy = Path(case['payload'])
    if sha(legacy) != case['payload_sha256']:
        raise ValueError('authenticated source differs')
    before = legacy.read_bytes()
    validate_inputs(before)
    source_rgba = before[0xa000:0xe000]
    source = bytearray(source_rgba)
    for i in range(0, len(source), 4):
        source[i], source[i+2] = source_rgba[i+2], source_rgba[i]
    expected = expected_pixels(source)
    nearest = expected_pixels(source, False)
    different = sum(abs(x-y) > 1 for x, y in zip(expected, nearest))
    if different < 128:
        raise ValueError('fractional fixture cannot distinguish nearest filtering')
    objects = []
    for name in ('runtime_encode', 'build_runtime_blur_fixture'):
        obj = out/(name+'.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here/(name+'.c'),
                        (a.registry_dir.resolve(),))
        objects.append(str(obj))
    exe = out/'builder'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    cases = []
    for bits in (16, 32):
        name = f'runtime_blur_linear_indexed_u{bits}_fractional_clamp'
        payload = out/(name+'-payload.bin')
        pixels = out/(name+'-expected.bin')
        subprocess.run([str(exe), str(legacy), str(payload), str(bits), '--linear'], check=True)
        data = payload.read_bytes()
        pixels.write_bytes(expected)
        if len(data) != 0x40000 or data[0x3a000:0x3e000] != source or \
                data[0x3e000:0x3f000] != bytes([0xcd])*4096:
            raise ValueError('input/output preparation changed')
        width = bits//8
        stream = b''.join(v.to_bytes(width, 'little') for v in (2, 0, 1, 2, 1, 3))
        if data[0x39c00:0x39c00+len(stream)] != stream:
            raise ValueError('actual reordered index stream changed')
        cases.append({'name': name, 'payload': str(payload), 'payload_sha256': sha(payload),
          'size': len(data), 'outputs': [{'name': 'pixels', 'offset': 0x3e000,
          'bytes': 4096, 'expected': str(pixels), 'expected_sha256': sha(pixels),
          'element_bytes': 1, 'tolerance': 1}],
          'immutable': [{'offset': 0x39c00, 'bytes': len(stream)},
                        {'offset': 0x3a000, 'bytes': 0x4000}, {'offset': 0x3f000, 'bytes': 4096}],
          'sampler': {'min': 'linear', 'mag': 'linear', 'address': 'clamp-to-edge', 'levels': 1},
          'uv_vertices': [[-1.75, .25], [62.25, .25], [-1.75, 64.25], [62.25, 64.25]],
          'oracle': 'Exact dyadic bilinear sampling of real binary source, actual16equal-tap DS8 and RGB EDR=.5; independent integer512denominator; left/bottom clamp boundaries; full4096bytes',
          'nearest_counterfactual_different_bytes_over_tolerance': different,
          'runtime_verified': False})
    (out/'manifest.json').write_text(json.dumps({'cases': cases}, indent=2)+'\n')
    print(f'Prepared two fractional indexed linear-blur GPU cases, nearest differs in{different}bytes; physical pixels pending')


if __name__ == '__main__':
    main()
