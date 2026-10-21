#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile actual path blend variants; never substitutes pixels or shader input."""
import argparse,hashlib,json,pathlib,re,subprocess,importlib.util

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fnv(p):
 h=0xcbf29ce484222325
 for b in p.read_bytes():h=((h^b)*0x100000001b3)&0xffffffffffffffff
 return f'{h:016x}'
def main():
 a=argparse.ArgumentParser(description=__doc__)
 for key in ('source-manifest','copy-suite','mesa-build','spirv-val','output'):a.add_argument('--'+key,required=True,type=pathlib.Path)
 r=a.parse_args();out=r.output.resolve();here=pathlib.Path(__file__).resolve().parent
 if here in out.parents or out==here:raise ValueError('private outputs outside source only')
 out.mkdir(parents=True,exist_ok=True);compiler=out/'path-midgard'
 subprocess.run(['python3',str(here/'build_path.py'),str(r.mesa_build),str(compiler)],check=True)
 originals=json.loads(r.source_manifest.read_text());copies=json.loads(r.copy_suite.read_text())
 result={'schema':1,'metallib_sha256':originals['metallib']['sha256'],'compiler_source_sha256':sha(here/'path_pair_midgard.c'),'programs':[],
  'claim':'Genuine inline tilebuffer blend compilation; new blend programs require their own GPU pixel proof.'}
 for name in ('path_rect','path_cubic','stroke_line'):
  original=next(p for p in originals['pairs'] if p['pair']==name);aux=24 if name=='stroke_line' else 16
  spv=[r.source_manifest.parent/(name+'.'+s+'.spv') for s in ('vert','frag')]
  for stage,path in zip(('vert','frag'),spv):
   if sha(path)!=original['spirv'][stage]['sha256']:raise ValueError('original SPIR-V changed')
   subprocess.run([str(r.spirv_val),str(path)],check=True)
  native=[out/(name+'.'+s+'.midgard') for s in ('vert','frag')];log=out/(name+'.log')
  with log.open('w') as f:subprocess.run([str(compiler),*map(str,spv),*map(str,native),*map(fnv,spv),str(aux),'runtime_blend'],stdout=f,stderr=subprocess.STDOUT,check=True)
  infos=re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+)',log.read_text())
  if len(infos)!=2:raise ValueError('missing native compiler receipts')
  stages={}
  for stage,path,info in zip(('vert','frag'),native,infos):
   entry=dict(zip(('bytes','first_tag','textures','work_regs','tls','wls'),map(int,info)))
   if entry['bytes']!=path.stat().st_size or entry['tls'] or entry['wls']:raise ValueError('unreviewed scratch/size')
   entry.update(path=str(path),sha256=sha(path));stages[stage]=entry
  record={'name':name,'stages':stages,'operation':'source_over_rt0_copy_rt1' if aux==24 else 'r32_add_logical_rt2',
   'original_spirv':{s:original['spirv'][s]['sha256'] for s in ('vert','frag')},'runtime_verified':False}
  if aux==24:
   copy=next(c for c in copies['cases'] if c['name']=='stroke_line_single_target')
   path=r.copy_suite.parent/'stroke_line.single.frag.midgard'
   if sha(path)!=copy['shader_sha256']['fragment']:raise ValueError('stroke copy stage changed')
   record['copy_fragment']={'path':str(path.resolve()),'bytes':path.stat().st_size,'first_tag':5,'textures':0,'work_regs':4,'tls':0,'wls':0,'sha256':sha(path)}
  result['programs'].append(record)
 (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
