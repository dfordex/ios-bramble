#!/usr/bin/env python3
"""Replay genuine stage publications through sparse Metal/native vertex layouts."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mesa-build', 'registry', 'publication',
                 'fragment-request', 'stock', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    vertex = parser.add_mutually_exclusive_group(required=True)
    vertex.add_argument('--vertex-request', type=Path)
    vertex.add_argument('--static-vertex603', action='store_true')
    a = parser.parse_args()
    here = Path(__file__).resolve().parent
    provider = here.parents[1] / 'a5mali-metal'
    out = a.output.resolve()
    if out == here or here in out.parents:
        parser.error('private outputs must remain outside the source tree')
    out.mkdir(parents=True, exist_ok=True)
    objects = []
    for name in ('runtime_encode', 'runtime_misc_encode', 'runtime_clear',
                 'runtime_path_encode', 'runtime_resource_ops', 'test_runtime_dynamic_format43'):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'))
        objects.append(str(obj))
    names = ('A5MaliBridge.c A5MaliNative.c A5MaliNativeUpload.c A5MaliCommandBuffer.m '
             'A5MaliRestrictedDevice.m A5MaliMetalAPI.m A5MaliMetalTexture.m '
             'A5MaliNativeTextureOps.m A5MaliShaderCompiledCache.m A5MaliShaderCompileRequest.m '
             'A5MaliMetalLibrary.m A5MaliDynamicShaderCache.m A5MaliDynamicPipeline.m '
             'A5MaliMetalDeviceResources.m A5MaliResourceDependencies.m A5MaliMetalUnsupportedSPI.m').split()
    exe = out / 'test-vertex-layout'
    command = ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
               '-DA5_MALI_HOST_TEST', '-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1',
               '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1', '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
               f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{a.publication.resolve()}"',
               '-DA5_SHADER_REQUEST_HOST_TEST=1', f'-DA5_SHADER_REQUEST_TEST_ROOT="{out / "requests"}"',
               '-I' + str(a.registry.resolve()), '-I' + str(out / 'preload-generated'),
               *[str(provider / n) for n in names], str(here / 'test_dynamic_vertex_layout.m'),
               *objects, '-framework', 'Foundation', '-framework', 'Metal',
               '-framework', 'IOSurface', '-framework', 'IOKit', '-o', str(exe)]
    subprocess.run(command, check=True)
    result = subprocess.run([str(exe), str(a.vertex_request.resolve()) if a.vertex_request else 'static603', str(a.fragment_request.resolve())],
                            env=dict(os.environ, A5_MALI_STOCK_QUARTZCORE_METALLIB=str(a.stock.resolve())),
                            text=True, capture_output=True)
    (out / 'test.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    (out / 'result.json').write_text(json.dumps({'host_replay_pass': True,
        'real_compiled_stages': True, 'mask_cases': 16, 'position_formats': [29, 31],
        'target_formats': [80, 43], 'blend_modes': [0, 1],
        'physical_gpu_result': 'pending'}, indent=2) + '\n')
    print(result.stdout.strip())


if __name__ == '__main__':
    main()
