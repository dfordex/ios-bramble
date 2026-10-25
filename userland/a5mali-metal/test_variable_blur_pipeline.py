#!/usr/bin/env python3
"""Load real stock blur publications and check production native descriptors."""
import argparse
from pathlib import Path
import subprocess
import sys
p=argparse.ArgumentParser(description=__doc__)
for name in ('registry','publication','stock','mesa-build','output'):
    p.add_argument('--'+name,required=True,type=Path)
a=p.parse_args();src=Path(__file__).resolve().parent;fam=src.parent/'a5xelte-air-translation/families'
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(fam));from build_runtime_encoder import compile_runtime
objects=[]
for name in ('runtime_encode','runtime_misc_encode','runtime_clear','runtime_path_encode','runtime_resource_ops','test_runtime_dynamic_format43','test_runtime_variable_blur'):
    obj=out/(name+'.o');compile_runtime(a.mesa_build.resolve(),obj,'host',fam/(name+'.c'));objects.append(str(obj))
names=('A5MaliBridge.c A5MaliNative.c A5MaliNativeUpload.c A5MaliCommandBuffer.m '
 'A5MaliRestrictedDevice.m A5MaliMetalAPI.m A5MaliMetalTexture.m A5MaliNativeTextureOps.m '
 'A5MaliShaderCompiledCache.m A5MaliShaderCompileRequest.m A5MaliMetalLibrary.m '
 'A5MaliDynamicShaderCache.m A5MaliDynamicPipeline.m A5MaliMetalDeviceResources.m A5MaliResourceDependencies.m test_variable_blur_pipeline.m').split()
command=['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
 '-DA5_MALI_HOST_TEST','-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1','-DA5_MALI_DYNAMIC_SHADER_COMPILER=1',
 '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{a.publication.resolve()}"',
 '-DA5_SHADER_REQUEST_HOST_TEST=1',f'-DA5_SHADER_REQUEST_TEST_ROOT="{out/"spool"}"',
 '-I'+str(a.registry.resolve()),*[str(src/n) for n in names],*objects,
 '-framework','Foundation','-framework','Metal','-framework','IOSurface','-framework','IOKit','-o',str(out/'test')]
subprocess.run(command,check=True)
subprocess.run([str(out/'test'),str(a.stock.resolve())],check=True)
