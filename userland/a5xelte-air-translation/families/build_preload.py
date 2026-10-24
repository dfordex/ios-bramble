#!/usr/bin/env python3
"""Compile real released-v4 colour preload shaders from source, outside Git."""
import argparse,hashlib,json,re,shlex,subprocess
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def build(build,out):
 here=Path(__file__).resolve().parent;out.mkdir(parents=True,exist_ok=True)
 stamp={'generator':sha(Path(__file__)), 'source':sha(here/'preload_midgard.c'),'raw_helper':sha(here/'misc_native_rt.h'),'mesa_build':str(build.resolve())}
 receipt=out/'preload.json';inc=out/'A5MaliPreloadData.inc'
 if receipt.exists() and inc.exists():
  old=json.loads(receipt.read_text())
  if old.get('inputs')==stamp and old.get('include_sha256')==sha(inc):return
 lines=subprocess.check_output(['ninja','-t','commands','src/panfrost/a5_t720_copy_shader'],cwd=build,text=True).splitlines()
 cc=shlex.split(next(x for x in lines if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in x));obj=out/'preload.o';exe=out/'preload-compiler'
 cc[cc.index('-c')+1]=str(here/'preload_midgard.c');cc[cc.index('-o')+1]=str(obj)
 for flag in ('-MD','-MQ','-MF'):
  if flag in cc:i=cc.index(flag);del cc[i:i+(1 if flag=='-MD' else 2)]
 subprocess.run(cc+['-Werror'],cwd=build,check=True)
 ld=shlex.split(lines[-1]);ld[ld.index('-o')+1]=str(exe);ld[ld.index('src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o')]=str(obj)
 subprocess.run(ld,cwd=build,check=True)
 records=[];parts=['/* Generated from our source using released Mesa; no Apple shader bytes. */']
 for fmt in (80,43,10,30,55,115):
  binary=out/f'preload-{fmt}.midgard';log=subprocess.check_output([str(exe),str(fmt),str(binary)],text=True);print(log.strip())
  values=dict((k,int(v))for k,v in re.findall(r'(\w+)=(\d+)',log));values.update(path=str(binary),sha256=sha(binary));records.append(values)
  parts.append(f'static const uint8_t a5_preload_{fmt}[]={{'+','.join(str(x)for x in binary.read_bytes())+'};')
 parts.append('static const A5PreloadShader a5_preload_shaders[]={'+','.join('{%d,a5_preload_%d,%d,%d,%d}'%(r['format'],r['format'],r['bytes'],r['tag'],r['regs'])for r in records)+'};')
 inc.write_text('\n'.join(parts)+'\n');receipt.write_text(json.dumps({'inputs':stamp,'shaders':records,'include_sha256':sha(inc)},indent=2)+'\n')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mesa-build',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();build(a.mesa_build.resolve(),a.output.resolve())
if __name__=='__main__':main()
