#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile actual original RAW204 SPIR-V with genuine inline source-over."""
import argparse,hashlib,json,pathlib,re,subprocess
from misc_compile import compile_backend

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for n in ('source-manifest','mesa-build','spirv-val','output'):p.add_argument('--'+n,type=pathlib.Path,required=True)
 a=p.parse_args();out=a.output.resolve();here=pathlib.Path(__file__).resolve().parent
 if here in out.parents:raise ValueError('private output directory required')
 out.mkdir(parents=True,exist_ok=True);j=json.loads(a.source_manifest.read_text())
 r=next(p for p in j['profiles'] if p['family']=='buffer_image_blit' and p['variant']=='rgba16f' and p['render_target']==0)
 prefix=a.source_manifest.parent/'buffer_image_blit_rgba16f';spv=[pathlib.Path(str(prefix)+'.'+s+'.spv') for s in ('vert','frag')]
 for s,path in zip(('vert','frag'),spv):
  if sha(path)!=r['spirv'][s]['sha256']:raise ValueError('original SPIR-V changed')
  subprocess.run([str(a.spirv_val),'--target-env','vulkan1.2','--uniform-buffer-standard-layout',str(path)],check=True)
 config=a.source_manifest.parent/'buffer_image_blit_rgba16f-profile.h';exe=out/'raw204-compile'
 if compile_backend(a.mesa_build.resolve(),config.resolve(),exe,out/'build.log',0,True,True):raise ValueError('actual compiler build failed')
 native=[out/('raw204.'+s+'.midgard') for s in ('vert','frag')];log=out/'compile.log'
 with log.open('w') as f:subprocess.run([str(exe),*map(str,spv),*map(str,native)],stdout=f,stderr=subprocess.STDOUT,check=True)
 info=re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+)',log.read_text());assert len(info)==2
 stages={}
 for s,path,values in zip(('vert','frag'),native,info):
  e=dict(zip(('bytes','first_tag','textures','work_regs','tls','wls'),map(int,values)));e.update(path=str(path),sha256=sha(path));stages[s]=e
  if e['tls'] or e['wls'] or e['first_tag']!=5:raise ValueError('unreviewed native scratch/tag')
 if stages['vert']['sha256']!=r['midgard']['vert']['sha256']:raise ValueError('inline fragment blend changed vertex unexpectedly')
 receipt={'schema':1,'profile_id':204,'logical_target':0,'metallib_sha256':j['metallib_sha256'],'source_manifest_sha256':sha(a.source_manifest),'original_spirv':{s:r['spirv'][s]['sha256'] for s in ('vert','frag')},'operation':'premultiplied_source_over_RGBA16Float','sample_count':1,'stages':stages,'runtime_verified':False,'claim':'Genuine released blend lowering and native framebuffer packing; device proof pending.'}
 (out/'manifest.json').write_text(json.dumps(receipt,indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
