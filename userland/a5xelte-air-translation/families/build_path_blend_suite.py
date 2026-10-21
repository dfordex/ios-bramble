#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Create real-shader blend tests with nonzero target and separate CPU oracle."""
import argparse,hashlib,json,pathlib,struct,subprocess
from build_preload import build as build_preload

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ('runtime-manifest','mesa-source','mesa-build','output'):p.add_argument('--'+k,type=pathlib.Path,required=True)
 a=p.parse_args();out=a.output.resolve();here=pathlib.Path(__file__).resolve().parent
 if here in out.parents:raise ValueError('private outputs required')
 out.mkdir(parents=True,exist_ok=True);builder=out/'build-path-blend-suite'
 preload_dir=out/'preload-generated';build_preload(a.mesa_build.resolve(),preload_dir)
 inc=[preload_dir,a.mesa_build/'src/panfrost',a.mesa_source/'src/panfrost',a.mesa_source/'src',a.mesa_source/'include',a.mesa_build/'include']
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-parameter',*['-I'+str(x) for x in inc],str(here/'build_path_blend_suite.c'),'-o',str(builder)],check=True)
 doc=json.loads(a.runtime_manifest.read_text());result={'schema':1,'cases':[],'claim':'New inline blend variants; host generated only, GPU proof pending.'}
 for r in doc['programs']:
  name=r['name'];kind={'path_rect':'rect','path_cubic':'cubic','stroke_line':'stroke'}[name];stroke=kind=='stroke';payload=out/(name+'-payload.bin')
  for s in ('vert','frag'):
   if sha(pathlib.Path(r['stages'][s]['path']))!=r['stages'][s]['sha256']:raise ValueError('native shader changed')
  subprocess.run([str(builder),kind,r['stages']['vert']['path'],r['stages']['frag']['path'],str(r['stages']['vert']['work_regs']),str(r['stages']['frag']['work_regs']),str(payload)],check=True)
  bpp=8 if stroke else 4;expected=bytearray(1024*bpp);mask=bytearray(1024*bpp);positive=0
  for y in range(32):
   for x in range(32):
    if stroke:
     inside=10<=x<22 and 14<=y<18;outside=x<6 or x>=26 or y<10 or y>=22
     # Src + Dst*(1-alpha), all values exact binary fractions.
     value=struct.pack('<4e',.25,.3125,.625,.75) if inside else struct.pack('<4e',.25,.125,.5,.5)
    else:
     inner=10<=x<22 and 10<=y<22
     inside=inner and (kind=='rect' or x+y>=36)
     outside=x<6 or x>=26 or y<6 or y>=26 or (inner and kind=='cubic' and x+y<=28)
     value=struct.pack('<f',1.25 if inside else .25)
    at=(y*32+x)*bpp;expected[at:at+bpp]=value
    if inside or outside:mask[at:at+bpp]=bytes([255])*bpp
    positive+=int(inside)
  if positive<16:raise ValueError('weak oracle')
  exp=out/(name+'-expected.bin');msk=out/(name+'-mask.bin');exp.write_bytes(expected);msk.write_bytes(mask)
  result['cases'].append({'name':name+'_inline_blend_nonzero','payload':str(payload),'payload_sha256':sha(payload),'outputs':[{'name':'source_over' if stroke else 'coverage_add','offset':0x20000,'bytes':len(expected),'expected':str(exp),'expected_sha256':sha(exp),'mask':str(msk),'mask_sha256':sha(msk),'element_bytes':2 if stroke else 4,'tolerance':0}],'immutable':[{'offset':0x4000,'bytes':0x4000},{'offset':0x10000,'bytes':0x5000},{'offset':0x30000,'bytes':0x1000}],'shader_sha256':{s:r['stages'][s]['sha256'] for s in ('vert','frag')},'oracle':'Nonzero old destination .25 coverage; stroke old(.25,.125,.5,.5),src(.125,.25,.375,.5). Edge mask excludes uncertain raster edges.','runtime_verified':False})
 (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
