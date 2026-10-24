#!/usr/bin/env python3
"""Replay a genuine worker fragment through production format80/43 paths."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('mesa-build', 'registry', 'publication', 'request', 'stock', 'output'):
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    here = Path(__file__).resolve().parent
    provider = here.parents[1] / 'a5mali-metal'
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    objects = []
    for name in ('runtime_encode', 'runtime_misc_encode', 'runtime_clear', 'runtime_path_encode', 'runtime_resource_ops', 'test_runtime_dynamic_format43'):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'))
        objects.append(str(obj))
    sources = ['A5MaliBridge.c', 'A5MaliNative.c', 'A5MaliNativeUpload.c', 'A5MaliCommandBuffer.m', 'A5MaliRestrictedDevice.m', 'A5MaliMetalAPI.m', 'A5MaliMetalTexture.m', 'A5MaliNativeTextureOps.m', 'A5MaliShaderCompiledCache.m', 'A5MaliShaderCompileRequest.m', 'A5MaliMetalLibrary.m', 'A5MaliDynamicShaderCache.m', 'A5MaliDynamicPipeline.m', 'A5MaliMetalDeviceResources.m', 'A5MaliResourceDependencies.m', 'A5MaliMetalUnsupportedSPI.m']
    exe = out / 'test-format43'
    command = ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror', '-DA5_MALI_HOST_TEST', '-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1', '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1', '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1', f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{a.publication.resolve()}"', '-DA5_SHADER_REQUEST_HOST_TEST=1', f'-DA5_SHADER_REQUEST_TEST_ROOT="{out / "requests"}"', '-I' + str(a.registry.resolve()), '-I' + str(out / 'preload-generated'), *[str(provider / s) for s in sources], str(here / 'test_dynamic_format43.m'), *objects, '-framework', 'Foundation', '-framework', 'Metal', '-framework', 'IOSurface', '-framework', 'IOKit', '-o', str(exe)]
    subprocess.run(command, check=True)
    import os
    env = dict(os.environ, A5_MALI_STOCK_QUARTZCORE_METALLIB=str(a.stock.resolve()))
    result = subprocess.run([str(exe), str(a.request.resolve())], env=env, text=True, capture_output=True)
    (out / 'test.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    preload = json.loads((out / 'preload-generated' / 'preload.json').read_text())
    report = {'request_sha256': sha(a.request), 'factory_formats': [80, 43], 'static_profiles': [602, 603, 604, 605, 606], 'static_profiles_owned_and_registry_immutable': True, 'copy_and_source_over': True, 'sfbd_internal_format43': 6, 'sfbd_writeback43': 28, 'target43_bytes_per_pixel': 2, 'preload_shaders': preload['shaders'], 'exact_original_code_preserved': True, 'bounds_and_unknown_formats_rejected': True, 'application_source43_still_rejected': True, 'device_runtime_verified': False}
    (out / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(result.stdout.strip())
    print(out / 'result.json')


if __name__ == '__main__':
    main()
