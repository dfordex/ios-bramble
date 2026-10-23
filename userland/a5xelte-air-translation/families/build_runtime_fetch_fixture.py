#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build independent ordered color-fetch pixel oracles outside the repository."""
import argparse,hashlib,json,subprocess
from pathlib import Path
from build_runtime_encoder import compile_runtime

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for arg in ('mesa-build','registry-dir','shader-dir','output'):p.add_argument('--'+arg,type=Path,required=True)
 p.add_argument('--noise',action='store_true')
 a=p.parse_args();here=Path(__file__).resolve().parent;out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 if here.parent==out or here.parent in out.parents:raise ValueError('private shader/payload output required')
 code=(a.shader_dir/'shader.midgard').read_bytes();info=json.loads((a.shader_dir/'shader.json').read_text())
 n=info['native_info']
 if not info['framebuffer_fetch'] or info['live_textures']!=([0,1]if a.noise else[0]) or n['tls'] or n['wls']:raise ValueError('wrong fixture stage ABI')
 (out/'A5FetchFixtureData.inc').write_text('static const uint8_t a5_fetch_code[]={'+','.join(str(x)for x in code)+'};\n'+
  f'#define A5_FETCH_NOISE {int(a.noise)}\n#define A5_FETCH_TAG {n["first_tag"]}\n#define A5_FETCH_REGS {n["work_regs"]}\n#define A5_FETCH_SHA "{hashlib.sha256(code).hexdigest()}"\n')
 objects=[]
 for source in ('runtime_misc_encode.c','build_runtime_fetch_fixture.c'):
  obj=out/(source+'.o');compile_runtime(a.mesa_build.resolve(),obj,'host',here/source,(a.registry_dir.resolve(),out));objects.append(str(obj))
 exe=out/'builder';subprocess.run(['cc',*objects,'-o',str(exe)],check=True)
 cases=[];src=(64,96,128,160);initial=(32,64,96,128)
 for overlapping in (False,True):
  name='ordered_fetch_'+('noise_'if a.noise else'')+('same_job_overlap'if overlapping else'full_target');payload=out/(name+'-payload.bin');expected=out/(name+'-expected.bin')
  subprocess.run([str(exe),str(payload),str(int(overlapping))],check=True)
  output=bytearray()
  for y in range(32):
   for x in range(32):
    value=list(initial)
    for _ in range(2 if overlapping and 8<=x<24 else 1):
     noise=(((x+y)%8)/8,(y%8)/8,(x%8)/8,0.5)if a.noise else(0,0,0,0)
     value=[round(v/2+s/4+n*255/8)for v,s,n in zip(value,src,noise)]
    output.extend(round(v)for v in value)
  expected.write_bytes(output);data=payload.read_bytes()
  assert len(data)==0x40000 and data[0x3e000:0x3f000]==bytes(initial)*1024 and output!=data[0x3e000:0x3f000]
  cases.append({'name':name,'payload':str(payload),'payload_sha256':sha(payload),'size':len(data),
   'outputs':[{'name':'pixels','offset':0x3e000,'bytes':4096,'expected':str(expected),'expected_sha256':sha(expected),'element_bytes':1,'tolerance':1}],
   'immutable':[{'offset':0x39000,'bytes':0x5000},{'offset':0x3f000,'bytes':4096}],
   'oracle':'Independent dst/2+sample/4; '+('two same-job rectangles overlap x=8..23'if overlapping else'one full-target rectangle'),
   'shader_sha256':hashlib.sha256(code).hexdigest()})
 (out/'manifest.json').write_text(json.dumps({'cases':cases,'reference':'Authored SubpassData SPIR-V, ordered native tilebuffer fetch'+(' with actual immutable-repeat RGBA16F/FragCoord resource ABI'if a.noise else'')},indent=2)+'\n')
 print('Prepared two actual emitted ordered-fetch GPU cases; device pixels pending')
if __name__=='__main__':main()
