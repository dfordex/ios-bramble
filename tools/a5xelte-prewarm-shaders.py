#!/usr/bin/env python3
"""Compile exact captured function requests on the Mac into private publications.
No generated Apple/native shader bytes belong in the source tree or Git.
"""
import argparse,hashlib,json,os,shutil,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def canonical(d):return json.dumps(d,sort_keys=True,separators=(',',':')).encode()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for key in ['requests','tools','stock','mesa-build','output']:p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();out=a.output.resolve()
 if out==ROOT or ROOT in out.parents:p.error('outputs must be private and outside the source checkout')
 out.mkdir(mode=0o700,exist_ok=False);tools=out/'tools';shutil.copytree(a.tools,tools)
 families=ROOT/'userland/a5xelte-air-translation/families';sys.path.insert(0,str(families))
 from misc_compile import compile_backend
 config=out/'dynamic-only.h';config.write_text('#define A5_PROFILE_COUNT 2\nstatic const struct a5_stage_profile kStages[2] = {{0},{0}};\n')
 assert compile_backend(a.mesa_build.resolve(),config,tools/'midgard-generic602',out/'backend.log')==0
 for name,mode in [('requests',0o1777),('cache',0o700),('compiled',0o755)]:
  (out/name).mkdir(mode=mode);(out/name).chmod(mode)
 owner=out/'requests'/str(os.geteuid())/'functions';owner.mkdir(parents=True,mode=0o700);owner.parent.chmod(0o700)
 keys=[]
 for path in sorted(a.requests.glob('*.request.json')):
  request=json.loads(path.read_text());key=request.pop('request_id');assert hashlib.sha256(canonical(request)).hexdigest()==key
  assert request['owner_uid']==os.geteuid(),'preserve exact captured UID/request identity'
  assert request['kind']=='function';request['request_id']=key
  dest=owner/(key+'.request.json');dest.write_bytes(canonical(request));dest.chmod(0o600);keys.append(key)
 assert keys
 worker=out/'worker';ios=families.parent/'ios'
 subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-Os','-Wall','-Wextra','-Werror','-DA5_SHADER_HOST_TEST=1',f'-DA5_TEST_TOOLS="{tools}"',f'-DA5_TEST_CACHE="{out}/cache"',f'-DA5_TEST_LIBRARY="{a.stock.resolve()}"',f'-DA5_TEST_REQUESTS="{out}/requests"',f'-DA5_TEST_PUBLISHED="{out}/compiled"',str(ios/'a5shader_compile.m'),'-framework','Foundation','-o',str(worker)],check=True)
 with (out/'worker.log').open('wb')as log:
  child=subprocess.Popen([str(worker),'--serve'],stdout=log,stderr=subprocess.STDOUT)
  try:
   while not all((out/'compiled'/key/'receipt.json').exists()for key in keys):
    if child.poll()is not None:raise RuntimeError('worker exited before real publication')
    time.sleep(.25)
  finally:child.terminate();child.wait(timeout=10)
 # Use the actual production cache loader, including reflection/ABI admission.
 mali=ROOT/'userland/a5mali-metal';loader=out/'cache-loader'
 subprocess.run(['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
  '-fsanitize=address,undefined','-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',
  f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{out}/compiled"',
  str(mali/'A5MaliDynamicShaderCache.m'),str(mali/'test_dynamic_shader_cache_publication.m'),
  '-framework','Foundation','-framework','Metal','-o',str(loader)],check=True)
 proofs=[]
 for key in keys:
  folder=out/'compiled'/key;r=json.loads((folder/'receipt.json').read_text());assert r['request_id']==key and r['stage_compiled']is True
  for part in ['native','reflection']:
   q=r[part];data=(folder/q['file']).read_bytes();assert len(data)==q['bytes']and hashlib.sha256(data).hexdigest()==q['sha256']
  subprocess.run([str(loader),str(owner/(key+'.request.json'))],check=True)
  proofs.append({'request_id':key,'native_bytes':r['native']['bytes'],'code_sha256':r['native']['sha256']})
 (out/'proof.json').write_text(json.dumps({'host_compile_only':True,'phone_pixels':'pending','stages':proofs},indent=2)+'\n')
 print('PASS',len(proofs),'exact real function publications, native/reflection hashes verified; physical GPU pending')
if __name__=='__main__':main()
