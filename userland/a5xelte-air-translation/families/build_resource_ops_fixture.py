#!/usr/bin/env python3
"""Build actual typed-copy/mip GPU fixtures from original source shaders."""
import argparse,hashlib,json,re,shlex,subprocess
from pathlib import Path
from build_resource_ops import build as build_shaders
from build_runtime_encoder import compile_runtime

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def build(mesa,out):
 out.mkdir(parents=True,exist_ok=True);here=Path(__file__).resolve().parent;gen=out/'generated';build_shaders(mesa,gen)
 objs=[]
 for s in ('runtime_resource_ops.c','build_resource_ops_fixture.c'):
  obj=out/(Path(s).stem+'.o');compile_runtime(mesa,obj,'host',here/s,[gen]);objs.append(obj)
 exe=out/'resource-fixture';subprocess.run(['cc',*[str(p)for p in objs],'-o',str(exe)],check=True)
 cases=[]
 # Captured 1D dimensions, exact bitwise payloads, and actual partial-tile
 # destination preservation. BGRA mip cases include source width776.
 specs=[(43,2,64,8,1,0),(23,0,3072,1,1,0),(25,0,4096,1,1,0),(55,0,4096,1,1,0),(105,0,1024,1,1,0),
        (10,2,64,8,1,0),(30,2,64,8,1,0),(80,2,64,8,1,0),(115,2,64,8,1,0),
        (80,2,64,32,0,1),(80,2,776,12,0,1),(80,2,3,1,0,1),(80,2,97,3,0,1),(80,2,1,3,0,1)]
 for f,t,w,h,partial,mip in specs:
  name=f'resource_{"mip"if mip else"copy"}_{f}_{"1d"if t==0 else"2d"}_{w}x{h}';payload=out/(name+'.bin');expected=out/(name+'-expected.bin')
  log=subprocess.check_output([str(exe),str(f),str(t),str(w),str(h),str(partial),str(mip),str(payload),str(expected)],text=True);v={k:int(n)for k,n in re.findall(r'(\w+)=(\d+)',log)};print(name,log.strip())
  mask=bytearray(b'\xff'*v['output_bytes'])
  width=max(1,w//2)if mip else w;height=max(1,h//2)if mip else h;bpp={10:1,30:2,43:2,23:2,25:2,55:4,80:4,105:8,115:8}[f]
  # SFBD writes actual texels, not allocation row-padding. Keep independent
  # row-padding outside oracle; source+guard bytes remain immutable checks.
  for y in range(height):mask[y*v['row_bytes']+width*bpp:(y+1)*v['row_bytes']]=b'\0'*(v['row_bytes']-width*bpp)
  mp=out/(name+'-mask.bin');mp.write_bytes(mask)
  cases.append({'name':name,'payload':str(payload),'size':payload.stat().st_size,'payload_sha256':sha(payload),
   'outputs':[{'name':'level','offset':v['output_offset'],'bytes':v['output_bytes'],'expected':str(expected),'expected_sha256':sha(expected),
    'element_bytes':1,'tolerance':1 if mip else 0,'mask':str(mp),'mask_sha256':sha(mp)}],
   'immutable':[{'offset':v['source_offset'],'bytes':v['source_bytes']},{'offset':0x3e000,'bytes':0x2000}],
   'operation':'four-texel center-scaled bilinear BGRA8 mip, matched against actual Mac Metal'if mip else'exact same-format bitwise copy; R8 normalized exact roundtrip',
   'source':v,'shader_receipt_sha256':sha(gen/'resource-ops.json')})
 manifest=out/'manifest.json';manifest.write_text(json.dumps({'shader_receipt':str(gen/'resource-ops.json'),'cases':cases},indent=2)+'\n');return manifest

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mesa-build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();print(build(a.mesa_build.resolve(),a.output.resolve()))
if __name__=='__main__':main()
