#!/usr/bin/env python3
"""Actual Mac Metal mip generation vs independent scaled-linear/fixed-box models.

Requires real Mac GPU access; a missing Metal device fails, never skips/PASSes.
Only RAM textures and files in --output are created; no phone is involved.
"""
import argparse,hashlib,json,math,subprocess
from pathlib import Path
SHAPES=((3,1),(97,3),(776,24),(65,5),(64,32),(1,3))
def compare(out):
 results=[]
 for w,h in SHAPES:
  for level in range(1,max(w,h).bit_length()):
   sw,sh=max(1,w>>(level-1)),max(1,h>>(level-1));dw,dh=max(1,w>>level),max(1,h>>level)
   source=out/f'{w}x{h}-level{level-1}.bin';dest=out/f'{w}x{h}-level{level}.bin';src=source.read_bytes();actual=dest.read_bytes()
   if len(src)!=sw*sh*4 or len(actual)!=dw*dh*4:raise ValueError('Metal output dimensions differ')
   linear=[];fixed=[]
   for y in range(dh):
    fy=(y+.5)*sh/dh-.5;y0=math.floor(fy);wy=fy-y0
    for x in range(dw):
     fx=(x+.5)*sw/dw-.5;x0=math.floor(fx);wx=fx-x0
     for c in range(4):
      fixed.append(math.floor(sum(src[(min(2*y+j,sh-1)*sw+min(2*x+i,sw-1))*4+c]for j in range(2)for i in range(2))/4+.5))
      v=sum(src[(max(0,min(y0+j,sh-1))*sw+max(0,min(x0+i,sw-1)))*4+c]*(wy if j else 1-wy)*(wx if i else 1-wx)for j in range(2)for i in range(2))
      linear.append(math.floor(v+.5))
   r={'parent':f'{w}x{h}','level':level,'source':f'{sw}x{sh}','destination':f'{dw}x{dh}','bytes':len(actual),
    'fixed_bad_tol1':sum(abs(a-b)>1 for a,b in zip(actual,fixed)),
    'linear_bad_tol1':sum(abs(a-b)>1 for a,b in zip(actual,linear)),
    'linear_max_error':max(abs(a-b)for a,b in zip(actual,linear)),
    'source_sha256':hashlib.sha256(src).hexdigest(),'actual_sha256':hashlib.sha256(actual).hexdigest(),
    'actual_first':list(actual[:4]),'fixed_first':fixed[:4],'linear_first':linear[:4]}
   results.append(r)
 doc={'source':str(Path(__file__).with_suffix('.m').resolve()),'per_step_tolerance':1,'levels':results}
 (out/'comparison.json').write_text(json.dumps(doc,indent=2)+'\n')
 if any(r['linear_bad_tol1']for r in results):raise ValueError('actual Metal differs from independent linear model')
 if not all(next(r for r in results if r['parent']==s and r['level']==1)['fixed_bad_tol1']for s in('3x1','97x3','1x3')):raise ValueError('odd-size counterexamples did not discriminate fixed box model')
 print(f'PASS actual Mac Metal {len(results)} mip reductions, all channels within1 of independent scaled-linear model; fixed2x2 rejected by3x1/97x3/1x3')
 return doc
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path);p.add_argument('--compare-only',action='store_true');a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 if not a.compare_only:
  exe=out/'metal-mip-reference';subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Foundation','-framework','Metal',str(Path(__file__).with_suffix('.m')), '-o',str(exe)],check=True)
  subprocess.run([str(exe),str(out)],check=True)
 compare(out)
if __name__=='__main__':main()
