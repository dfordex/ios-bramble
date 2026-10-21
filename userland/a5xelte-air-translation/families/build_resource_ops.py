#!/usr/bin/env python3
"""Build our original GPU copy/mip shaders using released Mesa26.2.4."""
import argparse,hashlib,json,re,shlex,subprocess
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def build(build,out):
 here=Path(__file__).resolve().parent;out.mkdir(parents=True,exist_ok=True)
 stamp={'source':sha(here/'resource_ops_midgard.c'),'mesa_build':str(build.resolve())}
 receipt=out/'resource-ops.json';inc=out/'A5MaliResourceOpsData.inc'
 if receipt.exists() and inc.exists():
  old=json.loads(receipt.read_text())
  if old.get('inputs')==stamp and old.get('include_sha256')==sha(inc) and all(sha(Path(r['path']))==r['sha256']for r in old['shaders']):return
 lines=subprocess.check_output(['ninja','-t','commands','src/panfrost/a5_t720_copy_shader'],cwd=build,text=True).splitlines()
 cc=shlex.split(next(x for x in lines if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in x));obj=out/'resource-ops.o';exe=out/'resource-ops-compiler'
 cc[cc.index('-c')+1]=str(here/'resource_ops_midgard.c');cc[cc.index('-o')+1]=str(obj)
 for flag in ('-MD','-MQ','-MF'):
  if flag in cc:i=cc.index(flag);del cc[i:i+(1 if flag=='-MD'else 2)]
 subprocess.run(cc+['-Werror'],cwd=build,check=True)
 ld=shlex.split(lines[-1]);ld[ld.index('-o')+1]=str(exe);ld[ld.index('src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o')]=str(obj)
 subprocess.run(ld,cwd=build,check=True)
 records=[];parts=['/* Generated from original resource-operation NIR by released Mesa. */']
 for kind,bits,dim in [(0,0,2)]+[(1,b,d)for b in(8,16,32,64)for d in(1,2)]+[(2,32,2)]:
  key=f'{kind}_{bits}_{dim}';binary=out/f'resource-{key}.midgard';log=subprocess.check_output([str(exe),str(kind),str(bits),str(dim),str(binary)],text=True);print(log.strip())
  r=dict((k,int(v))for k,v in re.findall(r'(\w+)=(\d+)',log));r.update(path=str(binary),sha256=sha(binary));records.append(r)
  parts.append(f'static const uint8_t a5_resource_{key}[]={{'+','.join(str(x)for x in binary.read_bytes())+'};')
 parts.append('static const A5ResourceShader a5_resource_shaders[]={'+','.join('{%d,%d,%d,a5_resource_%d_%d_%d,%d,%d,%d,%d,%d,%d}'%(r['kind'],r['bits'],r['dim'],r['kind'],r['bits'],r['dim'],r['bytes'],r['tag'],r['regs'],r['ubos'],r['attributes'],r['varyings'])for r in records)+'};')
 inc.write_text('\n'.join(parts)+'\n');receipt.write_text(json.dumps({'inputs':stamp,'shaders':records,'include_sha256':sha(inc)},indent=2)+'\n')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mesa-build',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
 p.add_argument('--runtime-output',type=Path);p.add_argument('--target',choices=('host','ios'),default='ios');p.add_argument('--test',action='store_true')
 a=p.parse_args();mesa=a.mesa_build.resolve();out=a.output.resolve();build(mesa,out)
 if a.runtime_output or a.test:
  from build_runtime_encoder import compile_runtime
  source=Path(__file__).with_name('runtime_resource_ops.c').resolve();obj=(a.runtime_output or out/'runtime-resource.o').resolve()
  compile_runtime(mesa,obj,a.target,source,[out])
  if a.test:
   if a.target!='host':p.error('--test requires --target host')
   testobj=out/'test-resource.o';exe=out/'test-resource';compile_runtime(mesa,testobj,'host',source.with_name('test_runtime_resource_ops.c'),[out])
   subprocess.run(['cc',str(obj),str(testobj),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
