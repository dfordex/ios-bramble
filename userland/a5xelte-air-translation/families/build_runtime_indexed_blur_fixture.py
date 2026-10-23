#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Two genuine indexed-blur GPU oracles using the independently verified blur8 reference."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('registry-dir','legacy-manifest','mesa-build','output'):
        p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();here=Path(__file__).resolve().parent;out=a.output.resolve()
    if here in out.parents or out==here:
        p.error('private fixture output required')
    out.mkdir(parents=True,exist_ok=True)
    receipt=json.loads((a.registry_dir/'compiled-registry.json').read_text())
    if sha(a.registry_dir/'A5MaliCompiledRegistryData.inc')!=receipt['include_sha256']:
        raise ValueError('registry receipt differs')
    case=next(c for c in json.loads(a.legacy_manifest.read_text())['cases']
              if c['name']=='downsample_8_frag_lph_bgra8')
    legacy=Path(case['payload']);reference=Path(case['outputs'][0]['expected'])
    if sha(legacy)!=case['payload_sha256'] or sha(reference)!=case['expected_sha256']:
        raise ValueError('authenticated reference differs')
    objects=[]
    for name in ('runtime_encode','build_runtime_blur_fixture'):
        obj=out/(name+'.o')
        compile_runtime(a.mesa_build.resolve(),obj,'host',here/(name+'.c'),(a.registry_dir.resolve(),))
        objects.append(str(obj))
    exe=out/'builder';subprocess.run(['cc',*objects,'-o',str(exe)],check=True)
    cases=[]
    for bits in (16,32):
        name=f'runtime_blur_indexed_u{bits}_reordered'
        payload=out/(name+'-payload.bin');expected=out/(name+'-expected.bin')
        subprocess.run([str(exe),str(legacy),str(payload),str(bits)],check=True)
        data=payload.read_bytes();expected.write_bytes(reference.read_bytes())
        if len(data)!=0x40000 or data[0x3e000:0x3f000]!=bytes([0xcd])*4096:
            raise ValueError('output was initialized with expected pixels')
        width=bits//8
        stream=b''.join(v.to_bytes(width,'little')for v in (2,0,1,2,1,3))
        if data[0x39c00:0x39c00+len(stream)]!=stream:
            raise ValueError('reordered index bytes differ')
        cases.append({'name':name,'payload':str(payload),'payload_sha256':sha(payload),'size':len(data),
          'outputs':[{'name':'pixels','offset':0x3e000,'bytes':4096,'expected':str(expected),
                      'expected_sha256':sha(expected),'element_bytes':1,'tolerance':1}],
          'immutable':[{'offset':0x39c00,'bytes':len(stream)},
                       {'offset':0x3a000,'bytes':0x4000},{'offset':0x3f000,'bytes':4096}],
          'oracle':'Existing independently verified blur8 arithmetic; same four vertices and complete rectangle, genuine reordered u16/u32 triangle indices',
          'runtime_verified':False})
    (out/'manifest.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
    print('Prepared two indexed blur GPU cases; device pixels pending')

if __name__=='__main__':
    main()
