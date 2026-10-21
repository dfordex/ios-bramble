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
 # Source-only format tests run against the same authenticated legacy bytes.
 test_obj=out/'test-input.o';compile_runtime(a.mesa_build.resolve(),test_obj,'host',here/'test_runtime_blur_input.c',(a.registry_dir.resolve(),))
 test_exe=out/'test-input';subprocess.run(['cc',objects[0],str(test_obj),'-o',str(test_exe)],check=True)
 subprocess.run([str(test_exe),str(old)],check=True)
 before=old.read_bytes()[0xa000:0xe000];after=payload.read_bytes()[0x3a000:0x3e000]
 converted=bytearray(before)
 for i in range(0,len(converted),4):converted[i],converted[i+2]=before[i+2],before[i]
 if after!=converted:raise ValueError('runtime source does not match exact RGBA->BGRA contract')
 source_contract={'legacy_format':'RGBA8Unorm','runtime_format':'BGRA8Unorm','width':64,'height':64,'row_bytes':256,
  'conversion':'swap input R/B bytes; preserve G/A; no output/oracle conversion',
  'legacy_source_sha256':hashlib.sha256(before).hexdigest(),'runtime_source_sha256':hashlib.sha256(after).hexdigest(),
  'changed_source_bytes':sum(a!=b for a,b in zip(before,after))}
 expected=out/'expected.bin';expected.write_bytes(expect.read_bytes())
 expected_bytes=expected.read_bytes();swapped=bytearray(expected_bytes)
 for i in range(0,len(swapped),4):swapped[i],swapped[i+2]=expected_bytes[i+2],expected_bytes[i]
 bad=next(i for i,(x,y)in enumerate(zip(swapped,expected_bytes))if abs(x-y)>1)
 prediction={'model':'incorrect RGBA input declared as BGRA swaps output R/B',
  'matched_bytes':sum(abs(x-y)<=1 for x,y in zip(swapped,expected_bytes)),'total_bytes':len(expected_bytes),
  'first_bad':bad,'predicted_actual':swapped[bad],'expected':expected_bytes[bad]}
 if prediction['matched_bytes']!=2962 or bad!=384 or swapped[bad]!=64 or expected_bytes[bad]!=0:
  raise ValueError('historical mismatch prediction changed')
 r={'name':'runtime_blur_dynamic_viewport_32x32','payload':str(payload),'payload_sha256':sha(payload),'size':0x40000,
 'outputs':[{'name':'pixels','offset':0x3e000,'bytes':0x1000,'expected':str(expected),'expected_sha256':sha(expected),'element_bytes':1,'tolerance':1}],
 'immutable':[{'offset':0x3a000,'bytes':0x4000},{'offset':0x3f000,'bytes':0x1000}],
 'oracle':'Existing authenticated blur8 CPU arithmetic; changed actual viewport32x32 with caller pixel-ortho MVP; shader sysval UBO0 scale/offset16 (not old540/960)',
 'source_input_contract':source_contract,'0178_counterfactual_prediction':prediction,
 'registry_include_sha256':receipt['include_sha256'],'runtime_source_sha256':sha(here/'runtime_encode.c'),'legacy_reference_manifest_sha256':sha(a.legacy_manifest)}
 (out/'manifest.json').write_text(json.dumps({'cases':[r]},indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
