#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise a real worker-published fetch stage through factory and emitter.

Requires private actual QuartzCore shaders. No GPU job is submitted. No fixture
or source Apple binary is written into the repository.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('registry', 'mesa-build', 'publication', 'request', 'metallib', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    a = parser.parse_args()
    here = Path(__file__).resolve().parent
    family = here.parent / 'a5xelte-air-translation/families'
    out = a.output.resolve()
    if here in out.parents or out == here:
        parser.error('private generated artifacts must remain outside the source tree')
    out.mkdir(parents=True, exist_ok=True)
    (out / "requests").mkdir(exist_ok=True)
    (out / "requests").chmod(0o1777)
    identity = json.loads(a.request.read_text())['request_id']
    if len(identity) != 64 or any(c not in '0123456789abcdef' for c in identity):
        parser.error('request must have its real canonical identity')
    publication = out / 'publication'
    publication.mkdir(exist_ok=True)
    stage = publication / identity
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(a.publication.resolve(), stage)
    for path in (publication, stage):
        path.chmod(0o755)
    for path in stage.iterdir():
        if path.is_file():
            path.chmod(0o444)
    spec = importlib.util.spec_from_file_location('fetch_runtime_build', family / 'build_runtime_encoder.py')
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.path.insert(0, str(family))
    spec.loader.exec_module(module)
    objects = []
    for name in ('runtime_encode', 'runtime_misc_encode', 'runtime_clear', 'runtime_path_encode', 'runtime_resource_ops'):
        obj = out / (name+'.o')
        module.compile_runtime(a.mesa_build.resolve(), obj, 'host', family/(name+'.c'))
        objects.append(str(obj))
    helper = out / 'fetch-emitter-test.o'
    module.compile_runtime(a.mesa_build.resolve(), helper, 'host', here/'test_framebuffer_fetch.c')
    objects.append(str(helper))
    sources = ['A5MaliBridge.c', 'A5MaliNative.c', 'A5MaliNativeUpload.c', 'A5MaliCommandBuffer.m',
               'A5MaliRestrictedDevice.m', 'A5MaliMetalAPI.m', 'A5MaliMetalTexture.m',
               'A5MaliNativeTextureOps.m', 'A5MaliShaderCompiledCache.m', 'A5MaliShaderCompileRequest.m',
               'A5MaliMetalLibrary.m', 'A5MaliDynamicShaderCache.m', 'A5MaliDynamicPipeline.m',
               'A5MaliMetalDeviceResources.m', 'test_framebuffer_fetch.m']
    exe = out / 'fetch-test'
    command = ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
               '-DA5_MALI_HOST_TEST', '-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1',
               '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1', '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
               '-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="'+str(publication)+'"',
               '-DA5_SHADER_REQUEST_HOST_TEST=1',
               '-DA5_SHADER_REQUEST_TEST_ROOT="'+str(out/'requests')+'"',
               '-I'+str(a.registry.resolve()), *[str(here/x) for x in sources], *objects,
               '-framework', 'Foundation', '-framework', 'IOSurface', '-framework', 'IOKit',
               '-framework', 'Metal', '-o', str(exe)]
    subprocess.run(command, check=True)
    env = dict(os.environ, A5_MALI_STOCK_QUARTZCORE_METALLIB=str(a.metallib.resolve()))
    subprocess.run([str(exe), str(a.request.resolve()), 'good'], env=env, check=True)
    receipt_path, reflection_path = stage/'receipt.json', stage/'reflection.json'
    original_receipt, original_reflection = receipt_path.read_bytes(), reflection_path.read_bytes()
    def write(path, data):
        path.chmod(0o644)
        path.write_bytes(data)
        path.chmod(0o444)
    try:
        reflection = json.loads(original_reflection)
        samplers = [b for s in reflection['layout']['sets'] for b in s['bindings'] if b['immutable_sampler']]
        assert len(samplers)==1
        samplers[0]['immutable_sampler']['address_mode_u'] = 2
        malformed = json.dumps(reflection, separators=(',', ':')).encode()
        receipt = json.loads(original_receipt)
        receipt['reflection']['bytes'] = len(malformed)
        receipt['reflection']['sha256'] = hashlib.sha256(malformed).hexdigest()
        write(reflection_path, malformed)
        write(receipt_path, json.dumps(receipt, separators=(',', ':')).encode())
        subprocess.run([str(exe), str(a.request.resolve()), 'bad-sampler'], env=env, check=True)
        write(reflection_path, original_reflection)
        receipt = json.loads(original_receipt)
        receipt['native']['first_tag'] = 5
        write(receipt_path, json.dumps(receipt, separators=(',', ':')).encode())
        subprocess.run([str(exe), str(a.request.resolve()), 'bad-tag'], env=env, check=True)
    finally:
        write(reflection_path, original_reflection)
        write(receipt_path, original_receipt)
    print('PASS actual framebuffer-fetch factory/emitter and rejected publication metadata; GPU pixels not tested')


if __name__ == '__main__':
    main()
