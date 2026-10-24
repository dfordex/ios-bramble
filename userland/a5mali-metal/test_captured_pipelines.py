#!/usr/bin/env python3
"""Replay private complete requests through the actual authenticated Metal factory."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
for name in ('registry', 'publication', 'requests', 'stock', 'mesa-build', 'output'):
    p.add_argument('--' + name, required=True, type=Path)
a = p.parse_args()
src = Path(__file__).resolve().parent
out = a.output.resolve()
if out == src or src in out.parents:
    p.error('private artifacts must stay outside the source tree')
out.mkdir(parents=True, exist_ok=True)
fam = src.parent / 'a5xelte-air-translation/families'
sys.path.insert(0, str(fam))
from build_runtime_encoder import compile_runtime
objects = []
for name in ('runtime_encode', 'runtime_misc_encode', 'runtime_clear',
             'runtime_path_encode', 'runtime_resource_ops'):
    obj = out / (name + '.o')
    compile_runtime(a.mesa_build.resolve(), obj, 'host', fam / (name + '.c'))
    objects.append(str(obj))
names = ('A5MaliBridge.c A5MaliNative.c A5MaliNativeUpload.c A5MaliCommandBuffer.m '
         'A5MaliRestrictedDevice.m A5MaliMetalAPI.m A5MaliMetalTexture.m '
         'A5MaliNativeTextureOps.m A5MaliShaderCompiledCache.m A5MaliShaderCompileRequest.m '
         'A5MaliMetalLibrary.m A5MaliDynamicShaderCache.m A5MaliDynamicPipeline.m '
         'A5MaliMetalDeviceResources.m A5MaliResourceDependencies.m test_captured_pipelines.m').split()
command = ['clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
           '-DA5_MALI_HOST_TEST', '-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1',
           '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1', '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
           f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{a.publication.resolve()}"',
           '-DA5_SHADER_REQUEST_HOST_TEST=1',
           f'-DA5_SHADER_REQUEST_TEST_ROOT="{out / "spool"}"',
           '-I' + str(a.registry.resolve()), *[str(src / n) for n in names], *objects,
           '-framework', 'Foundation', '-framework', 'Metal', '-framework', 'IOSurface',
           '-framework', 'IOKit', '-o', str(out / 'test')]
subprocess.run(command, check=True)
result = subprocess.run([str(out / 'test'), str(a.requests.resolve()), str(a.stock.resolve())],
                        text=True, capture_output=True,
                        env={k: v for k, v in os.environ.items() if k != 'A5_REPLAY_MISSING_REQUESTS'})
(out / 'replay.log').write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stdout + result.stderr
counts = re.search(r'COUNTS pass=(\d+) fail=(\d+) missing-stage=(\d+)', result.stdout)
assert counts and int(counts[1]) > 0 and int(counts[2]) == 0 and int(counts[3]) == 0, result.stdout
(out / 'result.json').write_text(json.dumps({'accepted': int(counts[1]), 'rejected': 0,
    'missing_stage': 0, 'exact_descriptor_roundtrip': True,
    'physical_gpu_execution': False}, indent=2) + '\n')
print(counts[0], '(actual factory, exact descriptors; host only)')
