#!/usr/bin/env python3
"""Build an actual runtime-encoder viewport GPU oracle using private real shaders."""
import argparse,json,hashlib,subprocess
from pathlib import Path
from build_runtime_encoder import compile_runtime

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for key in ('registry-dir','legacy-manifest','mesa-build','output'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);out=a.output.resolve();here=Path(__file__).resolve().parent
 receipt=json.loads((a.registry_dir/'compiled-registry.json').read_text())
 if sha(a.registry_dir/'A5MaliCompiledRegistryData.inc')!=receipt['include_sha256']:raise ValueError('registry receipt changed')
 c=next(c for c in json.loads(a.legacy_manifest.read_text())['cases'] if c['name']=='downsample_8_frag_lph_bgra8')
 old=Path(c['payload']);expect=Path(c['outputs'][0]['expected'])
 if sha(old)!=c['payload_sha256'] or sha(expect)!=c['expected_sha256']:raise ValueError('authenticated reference changed')
 objects=[]
 for name in ('runtime_encode','build_runtime_blur_fixture'):
  obj=out/(name+'.o');compile_runtime(a.mesa_build.resolve(),obj,'host',here/(name+'.c'),(a.registry_dir.resolve(),));objects.append(str(obj))
 exe=out/'builder';subprocess.run(['cc',*objects,'-o',str(exe)],check=True)
 payload=out/'payload.bin';subprocess.run([str(exe),str(old),str(payload)],check=True)
 expected=out/'expected.bin';expected.write_bytes(expect.read_bytes())
 r={'name':'runtime_blur_dynamic_viewport_32x32','payload':str(payload),'payload_sha256':sha(payload),'size':0x40000,
 'outputs':[{'name':'pixels','offset':0x3e000,'bytes':0x1000,'expected':str(expected),'expected_sha256':sha(expected),'element_bytes':1,'tolerance':1}],
 'immutable':[{'offset':0x3a000,'bytes':0x4000},{'offset':0x3f000,'bytes':0x1000}],
 'oracle':'Existing authenticated blur8 CPU arithmetic; changed actual viewport32x32 with caller pixel-ortho MVP; shader sysval UBO0 scale/offset16 (not old540/960)',
 'registry_include_sha256':receipt['include_sha256'],'runtime_source_sha256':sha(here/'runtime_encode.c'),'legacy_reference_manifest_sha256':sha(a.legacy_manifest)}
 (out/'manifest.json').write_text(json.dumps({'cases':[r]},indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
