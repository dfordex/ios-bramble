#!/usr/bin/env python3
"""Actual runtime RAW204 inline blend, nonzero destination and unchanged CPU oracle."""
import argparse,json,hashlib,subprocess,struct
from pathlib import Path
from build_runtime_encoder import compile_runtime

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ('registry-dir','legacy-manifest','mesa-build','output'):p.add_argument('--'+k,type=Path,required=True)
 a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);here=Path(__file__).resolve().parent
 receipt=json.loads((a.registry_dir/'compiled-registry.json').read_text())
 if sha(a.registry_dir/'A5MaliCompiledRegistryData.inc')!=receipt['include_sha256']:raise ValueError('registry changed')
 c=next(c for c in json.loads(a.legacy_manifest.read_text())['cases'] if c['name']=='buffer_image_blit_rgba16f_rt0');old=Path(c['payload'])
 if sha(old)!=c['payload_sha256']:raise ValueError('legacy resource input changed')
 objects=[]
 for name in ('runtime_misc_encode','build_runtime_raw204_fixture'):
  obj=out/(name+'.o');compile_runtime(a.mesa_build.resolve(),obj,'host',here/(name+'.c'),(a.registry_dir.resolve(),));objects.append(str(obj))
 exe=out/'builder';subprocess.run(['cc',*objects,'-o',str(exe)],check=True);payload=out/'payload.bin';subprocess.run([str(exe),str(old),str(payload)],check=True)
 expected=bytearray()
 for y in range(32):
  for x in range(32):
   on=(x//7+(31-y)//5)&1
   expected+=struct.pack('<4e',*( (.25,.3125,.625,.75) if on else (.25,.125,.5,.5)))
 exp=out/'expected.bin';exp.write_bytes(expected)
 case={'name':'runtime_raw204_inline_source_over_nonzero','payload':str(payload),'size':0x40000,'payload_sha256':sha(payload),
  'outputs':[{'name':'raw_source_over','offset':0x3c000,'bytes':8192,'expected':str(exp),'expected_sha256':sha(exp),'element_bytes':2,'tolerance':0}],
  'immutable':[{'offset':0x20000,'bytes':0x10000},{'offset':0x3e000,'bytes':0x2000}],
  'registry_include_sha256':receipt['include_sha256'],'oracle':'Actual AIR byte-mask vertical flip; true premultiplied source(.125,.25,.375,.5)+nonzero destination(.25,.125,.5,.5)*(1-srcAlpha). Zero mask preserves old destination; exact binary16 arithmetic.','runtime_verified':False}
 cases=[case]
 # These are separate checks: actual admitted R8 Bsov, then a standalone
 # physical RG8 preload copy (not an invented Metal draw profile).
 r8input=next(c for c in json.loads(a.legacy_manifest.read_text())['cases'] if c['name']=='buffer_image_blit_r8_rt0')
 r8old=Path(r8input['payload'])
 if sha(r8old)!=r8input['payload_sha256']:raise ValueError('legacy R8 input changed')
 for mode in ('r8','rg8'):
  payload=out/(mode+'-payload.bin');subprocess.run([str(exe),str(r8old),str(payload),mode],check=True)
  expected=bytearray()
  for y in range(32):
   for x in range(32):
    if mode=='rg8':expected+=bytes(((x*7+y*3)&255,(x*11+y*17)&255))
    else:
     inside=8<=x<24 and 8<=y<24;on=(x//7+(31-y)//5)&1
     expected+=bytes((64 if inside and on else 192,))
  exp=out/(mode+'-expected.bin');exp.write_bytes(expected)
  immutable=[{'offset':0x20000,'bytes':0x10000},{'offset':0x3e000,'bytes':0x2000}]
  if mode=='rg8':immutable.append({'offset':0x3b000,'bytes':2048})
  cases.append({'name':'runtime_r8_partial_scissor_source_over_nonzero' if mode=='r8' else 'standalone_rg8_textured_preload_copy',
   'payload':str(payload),'size':0x40000,'payload_sha256':sha(payload),
   'outputs':[{'name':'pixels','offset':0x3c000,'bytes':len(expected),'expected':str(exp),'expected_sha256':sha(exp),'element_bytes':1,'tolerance':1}],
   'immutable':immutable,'registry_include_sha256':receipt['include_sha256'],
   'oracle':'R8 actual AIR keeps vec4/alpha: mask1 gives tint(.25,.5,.75,1), mask0 giveszero, so SourceOver preserves192 whenmask0/outside16x16scissor.' if mode=='r8' else 'Standalone released-NIR RG8 texture preload copy from nonconstant two-channel source to poisoned target; main application draw colour writes disabled. Not Metal pipeline coverage.',
   'runtime_verified':False})
 (out/'manifest.json').write_text(json.dumps({'cases':cases},indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
