#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Real104/BGRA8 and108/RGBA16 blur pixel tests; independent legacy references."""
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
    legacy_cases=json.loads(a.legacy_manifest.read_text())['cases']
    objects=[]
    for name in ('runtime_encode','build_runtime_blur_fixture'):
        obj=out/(name+'.o')
        compile_runtime(a.mesa_build.resolve(),obj,'host',here/(name+'.c'),(a.registry_dir.resolve(),))
        objects.append(str(obj))
    exe=out/'builder';subprocess.run(['cc',*objects,'-o',str(exe)],check=True)
    cases=[]
    for profile,case_name in ((104,'narrow_blur_19_frag_lph_bgra8'),
                               (108,'narrow_blur_23_frag_lph_rgba16f')):
        case=next(c for c in legacy_cases if c['name']==case_name)
        legacy=Path(case['payload']);reference=Path(case['outputs'][0]['expected'])
        if sha(legacy)!=case['payload_sha256'] or sha(reference)!=case['expected_sha256']:
            raise ValueError('authenticated independent reference differs')
        name=f'runtime_inactive_rt1_profile{profile}_indexed'
        payload=out/(name+'-payload.bin');expected=out/(name+'-expected.bin')
        bits=16 if profile==104 else 32
        subprocess.run([str(exe),str(legacy),str(payload),str(bits),f'--profile={profile}'],check=True)
        data=payload.read_bytes();expected.write_bytes(reference.read_bytes())
        count=4096 if profile==104 else 8192
        if len(data)!=0x40000 or data[0x3e000:0x3e000+count]!=bytes([0xcd])*count:
            raise ValueError('output was initialized with expected pixels')
        width=bits//8
        stream=b''.join(v.to_bytes(width,'little')for v in (2,0,1,2,1,3))
        if data[0x39c00:0x39c00+len(stream)]!=stream:
            raise ValueError('reordered index bytes differ')
        guard={'offset':0x3f000,'bytes':4096} if profile==104 else {'offset':0x39d00,'bytes':768}
        cases.append({'name':name,'payload':str(payload),'payload_sha256':sha(payload),'size':len(data),
          'outputs':[{'name':'pixels','offset':0x3e000,'bytes':count,'expected':str(expected),
                      'expected_sha256':sha(expected),'element_bytes':1 if profile==104 else 2,'tolerance':1}],
          'immutable':[{'offset':0x39c00,'bytes':len(stream)},
                       {'offset':0x3a000,'bytes':0x4000},guard],
          'oracle':'Existing independent real19/23tap arithmetic and EDR reference; native caller MVP and reordered indices; no expected output enters input descriptors',
          'scope':'GPU pixel output for the actual shader; omitted-RT1 factory/allocation/fence contracts tested by real IOSurface host integration separately',
          'runtime_verified':False})
    (out/'manifest.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
    print('Prepared profile104/BGRA8 and108/RGBA16 indexed blur cases; device pixels pending')

if __name__=='__main__':
    main()
