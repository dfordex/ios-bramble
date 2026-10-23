#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Append genuine unknown-stage dynamic-provider GPU pixel oracles privately."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def expected(blend):
    out = bytearray()
    for y in range(32):
        for x in range(32):
            a = (x * 5 + y * 7 + 13) & 255
            out.extend(round(a + dest * (255 - a) / 255) if blend else a
                       for dest in (32, 64, 96, 128))
    return bytes(out)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('registry-dir', 'mesa-build', 'publication', 'spool', 'capture', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    here = Path(__file__).resolve().parent
    provider = here.parents[1] / 'a5mali-metal'
    out = a.output.resolve()
    if here.parent == out or here.parent in out.parents:
        p.error('generated executable shaders and payloads must remain private')
    out.mkdir(parents=True, exist_ok=True)
    registry = a.registry_dir.resolve()
    capture = json.loads(a.capture.read_text())
    if capture['function'] != 'fixed_frag_lph_cph' or len(capture['constants']) != 58 or \
            capture['constants']['fc_coord_function0']['raw'] != '00' or \
            capture['constants']['fc_image_function0']['raw'] != '11':
        raise ValueError('this oracle tests the actual unknown coord0/image17 request')
    native = []
    for file in a.publication.glob('*/receipt.json'):
        receipt = json.loads(file.read_text())
        if receipt.get('kind') == 'dynamic-stage' and receipt.get('stage') == 'fragment' and receipt.get('native'):
            native.append({'receipt': str(file), 'receipt_sha256': sha(file),
                           'native': receipt.get('native'), 'native_abi': receipt.get('native_abi')})
    objects = []
    for family, name in (('misc', 'runtime_misc_encode'), ('blur', 'runtime_encode'),
                         ('clear', 'runtime_clear'), ('path', 'runtime_path_encode'),
                         ('resource', 'runtime_resource_ops'), ('fixture', 'build_runtime_dynamic_fixture')):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'), (registry,))
        objects.append(str(obj))
    sources = ['A5MaliBridge.c', 'A5MaliNative.c', 'A5MaliNativeUpload.c', 'A5MaliCommandBuffer.m',
               'A5MaliRestrictedDevice.m', 'A5MaliMetalAPI.m', 'A5MaliMetalTexture.m',
               'A5MaliNativeTextureOps.m', 'A5MaliShaderCompiledCache.m', 'A5MaliShaderCompileRequest.m',
               'A5MaliMetalLibrary.m', 'A5MaliDynamicShaderCache.m', 'A5MaliDynamicPipeline.m',
               'A5MaliMetalDeviceResources.m', 'A5MaliResourceDependencies.m']
    exe = out / 'builder'
    command = ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
        '-DA5_MALI_HOST_TEST', '-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1',
        '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1', '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
        '-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="' + str(a.publication.resolve()) + '"',
        '-DA5_SHADER_REQUEST_HOST_TEST=1', '-DA5_SHADER_REQUEST_TEST_ROOT="' + str(a.spool.resolve()) + '"',
        '-I' + str(registry), *[str(provider / x) for x in sources],
        str(here / 'build_runtime_dynamic_fixture.m'), *objects,
        '-framework', 'Foundation', '-framework', 'IOSurface', '-framework', 'IOKit',
        '-framework', 'Metal', '-o', str(exe)]
    subprocess.run(command, check=True)
    cases = []
    for blend in (False, True):
        name = 'dynamic_unknown_a8_alpha_' + ('source_over' if blend else 'copy')
        payload, oracle = out / (name + '-payload.bin'), out / (name + '-expected.bin')
        subprocess.run([str(exe), str(a.capture.resolve()), str(payload), 'blend' if blend else 'copy'], check=True)
        data = payload.read_bytes()
        if len(data) != 0x40000:
            raise ValueError('native payload length differs')
        initial = bytes((32, 64, 96, 128)) * 1024 if blend else bytes([0xcd]) * 4096
        if data[0x3e000:0x3f000] != initial:
            raise ValueError('output was prerendered on CPU')
        source = bytes((x * 5 + y * 7 + 13) & 255 for y in range(32) for x in range(32))
        if data[0x3a000:0x3a400] != source:
            raise ValueError('source alpha contract differs')
        reference = expected(blend)
        oracle.write_bytes(reference)
        wrong = bytes(v for a in source for v in (0, 0, 0, a))
        if not blend and sum(abs(x-y) > 1 for x, y in zip(reference, wrong)) < 2500:
            raise ValueError('oracle does not distinguish an old direct-sample shader')
        cases.append({'name': name, 'payload': str(payload), 'payload_sha256': sha(payload), 'size': len(data),
            'outputs': [{'name': 'pixels', 'offset': 0x3e000, 'bytes': 4096,
                'expected': str(oracle), 'expected_sha256': sha(oracle), 'element_bytes': 1, 'tolerance': 1}],
            'immutable': [{'offset': 0x39000, 'bytes': 0x5000}, {'offset': 0x3f000, 'bytes': 4096}],
            'dynamic_profile_id': 65536, 'capture_sha256': sha(a.capture),
            'runtime_source_sha256': sha(here / 'runtime_misc_encode.c'),
            'provider_source_sha256': sha(provider / 'A5MaliDynamicPipeline.m'),
            'oracle': 'Independent A8(x*5+y*7+13) sampled at normalized pixel centres; alpha replicated to BGRA' +
                (' then premultiplied source-over fixed BGRA(32,64,96,128)' if blend else ''),
            'runtime_verified': False})
    manifest = {'cases': cases, 'root_dynamic_publications': native}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(out / 'manifest.json')


if __name__ == '__main__':
    main()
