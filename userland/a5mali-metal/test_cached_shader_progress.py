#!/usr/bin/env python3
"""Build the actual provider and test cached stage/factory progress under a held UID lock.
Requires private genuine registry/publication/request/stock inputs. No GPU claims.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

p=argparse.ArgumentParser(description=__doc__)
for name in ('registry','published','request','library','mesa-build'):
    p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--work-dir',type=Path)
a=p.parse_args()
out=a.work_dir or Path(tempfile.mkdtemp(prefix='a5-cached-progress-',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True)
src=Path(__file__).resolve().parent
objects=[]
for family in ('encoder','misc','clear','path','resource'):
    obj=out/('runtime-'+family+'.o')
    cmd=['python3',str(src.parent/'a5xelte-air-translation/families/build_runtime_encoder.py'),
         '--mesa-build',str(a.mesa_build),'--target','host','--output',str(obj)]
    if family!='encoder':cmd+=['--family',family]
    subprocess.run(cmd,check=True)
    objects.append(str(obj))
names=['A5MaliBridge.c','A5MaliNative.c','A5MaliNativeUpload.c','A5MaliCommandBuffer.m',
       'A5MaliRestrictedDevice.m','A5MaliMetalAPI.m','A5MaliMetalTexture.m','A5MaliNativeTextureOps.m',
       'A5MaliShaderCompiledCache.m','A5MaliShaderCompileRequest.m','A5MaliMetalLibrary.m',
       'A5MaliDynamicShaderCache.m','A5MaliDynamicPipeline.m','A5MaliMetalDeviceResources.m',
       'A5MaliResourceDependencies.m','A5MaliMetalUnsupportedSPI.m','test_cached_shader_progress.m']
spool=out/'requests'
cmd=['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
     '-DA5_MALI_HOST_TEST','-DA5_MALI_REQUIRE_COMPILED_REGISTRY=1',
     '-DA5_MALI_DYNAMIC_SHADER_COMPILER=1','-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
     '-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="'+str(a.published)+'"',
     '-DA5_SHADER_REQUEST_HOST_TEST=1','-DA5_SHADER_REQUEST_TEST_ROOT="'+str(spool)+'"',
     '-I'+str(a.registry),*[str(src/n) for n in names],*objects,
     '-framework','Foundation','-framework','IOSurface','-framework','IOKit','-framework','Metal',
     '-o',str(out/'test')]
subprocess.run(cmd,check=True)
subprocess.run([str(out/'test'),str(a.request),str(a.library),str(spool)],timeout=10,check=True)
