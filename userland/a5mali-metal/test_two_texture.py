#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise genuine two-texture dual-UV stages through the factory and emitter.

Requires private actual QuartzCore shaders. No GPU job is submitted. No fixture
or source Apple binary is written into the repository.
"""
import argparse
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
    parser.add_argument('--vertex-publication', type=Path, required=True)
    parser.add_argument('--vertex-request', type=Path, required=True)
    parser.add_argument('--fixture-dir', type=Path)
    a = parser.parse_args()
    if bool(a.vertex_publication) != bool(a.vertex_request):
        parser.error('vertex publication and request must be supplied together')
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
    spec = importlib.util.spec_from_file_location('two_texture_runtime_build', family / 'build_runtime_encoder.py')
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.path.insert(0, str(family))
    spec.loader.exec_module(module)
    objects = []
    for name in ('runtime_encode', 'runtime_misc_encode', 'runtime_clear', 'runtime_path_encode', 'runtime_resource_ops'):
        obj = out / (name+'.o')
        module.compile_runtime(a.mesa_build.resolve(), obj, 'host', family/(name+'.c'))
        objects.append(str(obj))
    helper = out / 'two-texture-emitter-test.o'
    module.compile_runtime(a.mesa_build.resolve(), helper, 'host', here/'test_two_texture.c')
    objects.append(str(helper))
    sources = ['A5MaliBridge.c', 'A5MaliNative.c', 'A5MaliNativeUpload.c', 'A5MaliCommandBuffer.m',
               'A5MaliRestrictedDevice.m', 'A5MaliMetalAPI.m', 'A5MaliMetalTexture.m',
               'A5MaliNativeTextureOps.m', 'A5MaliShaderCompiledCache.m', 'A5MaliShaderCompileRequest.m',
               'A5MaliMetalLibrary.m', 'A5MaliDynamicShaderCache.m', 'A5MaliDynamicPipeline.m',
               'A5MaliMetalDeviceResources.m', 'A5MaliResourceDependencies.m', 'test_two_texture.m']
    exe = out / 'two-texture-test'
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
    vertex_identity=json.loads(a.vertex_request.read_text())['request_id']
    vertex_stage=publication / vertex_identity
    if vertex_stage.exists():
        shutil.rmtree(vertex_stage)
    shutil.copytree(a.vertex_publication.resolve(), vertex_stage)
    vertex_stage.chmod(0o755)
    for path in vertex_stage.iterdir():
        if path.is_file():
            path.chmod(0o444)
    if a.fixture_dir:
        a.fixture_dir.mkdir(parents=True, exist_ok=True)
        env['A5_TWO_TEXTURE_FIXTURE']=str(a.fixture_dir.resolve()/'actual_two_texture_dual_uv-payload.bin')
    subprocess.run([str(exe), str(a.request.resolve()), str(a.vertex_request.resolve())], env=env, check=True)
    # Keep native code unchanged: each malformed metadata case is rehashed
    # into a root-owned private copy and must reject before pipeline creation.
    import hashlib
    receipt_path, reflection_path=stage/'receipt.json', stage/'reflection.json'
    original_receipt, original_reflection=receipt_path.read_bytes(),reflection_path.read_bytes()
    def replace(path,data):
        path.chmod(0o644);path.write_bytes(data);path.chmod(0o444)
    try:
        for fault in ('unknown-synthetic','invalid-blob','live-blob','out-of-push-read'):
            receipt=json.loads(original_receipt);reflection=json.loads(original_reflection)
            binding=next(b for s in reflection['layout']['sets'] for b in s['bindings'] if 'Synthetic' in b['source'])
            if fault=='unknown-synthetic':
                binding['source']['Synthetic']['binding']='UnimplementedBlob'
            elif fault=='invalid-blob':
                next(s for s in reflection['stages'] if s['stage']=='frag')['constant_blob']='zz'
            elif fault=='live-blob':
                receipt['native_abi']['native_info']['ubos']=6
                receipt['native_abi']['live_ubos'].append({'native_index':binding['binding']+1,'min_bytes':8})
            else:
                receipt['native_abi']['sysval_ubo0_read_extent']=96
                next(u for u in receipt['native_abi']['live_ubos'] if u['native_index']==0)['min_bytes']=96
            encoded=json.dumps(reflection,separators=(',',':')).encode()
            receipt['reflection']['bytes']=len(encoded);receipt['reflection']['sha256']=hashlib.sha256(encoded).hexdigest()
            replace(reflection_path,encoded);replace(receipt_path,json.dumps(receipt,separators=(',',':')).encode())
            subprocess.run([str(exe),str(a.request.resolve()),str(a.vertex_request.resolve()),'reject-cache'],env=env,check=True)
    finally:
        replace(receipt_path,original_receipt);replace(reflection_path,original_reflection)
    if a.fixture_dir:
        def digest(path):
            import hashlib
            return hashlib.sha256(path.read_bytes()).hexdigest()
        fixture=a.fixture_dir.resolve()
        payload=fixture/'actual_two_texture_dual_uv-payload.bin'
        expected=fixture/'actual_two_texture_dual_uv-expected.bin'
        pixels=bytearray()
        # Stock optimized NIR: sample0RGBA * interpolated vertexRGBA *
        # sample1Alpha. UV0 has quarter-texel offsets but nearest still picks
        # (x,y). UV1 mirrors X and lands between neighboring texel centers;
        # linear clamp yields their average. The two source RGB patterns and
        # vertex factors are deliberately different; no output enters jobs.
        for y in range(32):
            for x in range(32):
                j0,j1=31-x,min(31,32-x)
                alpha=lambda j:(j*j*7+j*31+29)%256
                weight=(alpha(j0)+alpha(j1))/(2*255)
                source=(32+(x*23+y*9)%192,32+(x*7+y*19)%192,
                        32+(x*x*11+y*5)%192,192)
                pixels.extend(round(c*factor*weight) for c,factor in zip(source,(1,.25,.5,.5)))
        expected.write_bytes(pixels)
        raw=payload.read_bytes()
        assert len(raw)==0x40000 and len(pixels)==4096 and raw[0x3e000:0x3f000]!=pixels
        fs_receipt=json.loads((a.publication/'receipt.json').read_text())
        vs_receipt=json.loads((a.vertex_publication/'receipt.json').read_text())
        assert raw[0x6000:0x6000+2592]==(a.vertex_publication/'stage.midgard').read_bytes()
        assert raw[0x8000:0x8000+1328]==(a.publication/'stage.midgard').read_bytes()
        case={'name':'actual_two_texture_dual_uv_nearest_linear','payload':str(payload),
              'payload_sha256':digest(payload),'size':len(raw),
              'outputs':[{'name':'pixels','offset':0x3e000,'bytes':4096,
                          'expected':str(expected),'expected_sha256':digest(expected),
                          'element_bytes':1,'tolerance':1}],
              'immutable':[{'offset':0x39000,'bytes':4096},
                           {'offset':0x3b000,'bytes':12288},
                           {'offset':0x3f000,'bytes':4096}],
              'oracle':'Actual NIR sample0RGBA * vertexRGBA * sample1Alpha; independent nearest/linear sampling of different 32x32 images with distinct quarter-texel UV0 and mirrored half-texel UV1',
              'shader_sha256':fs_receipt['native']['sha256'],
              'vertex_sha256':vs_receipt['native']['sha256']}
        (fixture/'manifest.json').write_text(json.dumps({'cases':[case],
            'reference':'Actual host worker publications, full target independent byte oracle',
            'pixel_result':'pending physical GPU execution'},indent=2)+'\n')
    print('PASS actual two-texture dual-UV integration; GPU pixels not tested')


if __name__ == '__main__':
    main()
