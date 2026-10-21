#!/usr/bin/env python3
"""Build private actual-QC misc GPU payloads and independent pixel oracles.

Consumes a full-attachment misc_compile.py manifest; generates nine separate
SFBD cases. The real read-only AIR writes equal values to RT0/RT1 for blit/clear,
so independent per-target replay preserves both outputs without native MRT.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import struct
import subprocess


def compile_builder(build,output):
    source=Path(__file__).with_name('build_misc_suite.c').resolve()
    lines=subprocess.check_output(['ninja','-t','commands','src/panfrost/a5_t720_copy_shader'],cwd=build,text=True).splitlines()
    cc=shlex.split(next(l for l in lines if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in l))
    obj=output.with_suffix('.o');cc[cc.index('-c')+1]=str(source);cc[cc.index('-o')+1]=str(obj);cc+=['-Werror']
    for flag in ('-MD','-MQ','-MF'):
        if flag in cc:
            i=cc.index(flag);del cc[i:i+(1 if flag=='-MD' else 2)]
    subprocess.run(cc,cwd=build,check=True)
    subprocess.run(['cc',str(obj),'-o',str(output)],check=True)


def expected(family,variant,target):
    data=bytearray()
    for y in range(32):
        for x in range(32):
            if family=='attachment_clear':data+=bytes(4);continue
            if family=='home_affordance':
                level=192 if ((x//7+y//5)&1) else 64
                data+=bytes((level,level,level,255));continue
            on=((x//7+(31-y)//5)&1)
            if variant=='rgba16f':data+=struct.pack('<4H',*( (0x3400,0x3800,0x3a00,0x3c00) if on else (0,0,0,0)))
            elif variant=='r8':
                data+=bytes((64,128)) if on and target==1 else bytes((0,0)) if target==1 else bytes((64 if on else 0,))
            else:data+=bytes((191,128,64,255)) if on else bytes(4)
    return bytes(data)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiled-manifest',type=Path,required=True)
    parser.add_argument('--mesa-build',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    if any(out.iterdir()):parser.error('--output must be empty')
    if Path(__file__).resolve().parents[1] in out.parents:parser.error('private output must stay outside source')
    manifest=json.loads(args.compiled_manifest.read_text());compiler_dir=args.compiled_manifest.resolve().parent
    builder=out/'build-misc-suite';compile_builder(args.mesa_build.resolve(),builder)
    result={'gpu_va':0x02000000,'payload_bytes':0x40000,'device_runtime_verified':False,'cases':[]}
    for profile in manifest['profiles']:
        if profile['status']!='compiled':raise ValueError('incomplete shader profile')
        family,variant,target=profile['family'],profile['variant'],profile['render_target']
        want=[0] if family=='home_affordance' else [0,1]
        if profile['full_air_output_targets']!=want:raise ValueError('actual MRT outputs were not preserved')
        name=family+'_'+variant+'_rt'+str(target);prefix=compiler_dir/name
        shaders=[Path(str(prefix)+'.'+stage+'.midgard') for stage in ('vert','frag')]
        for stage,path in zip(('vert','frag'),shaders):
            info=profile['midgard'][stage];b=path.read_bytes()
            if len(b)!=info['bytes'] or hashlib.sha256(b).hexdigest()!=info['sha256'] or info['tls'] or info['wls']:
                raise ValueError('shader differs from authenticated zero-TLS family profile')
        fmt=3 if variant=='r8' and target==1 else {'bgra8':0,'r8':1,'rgba16f':2}[variant]
        payload=out/(name+'.payload.bin');oracle=out/(name+'.expected.bin')
        subprocess.run([str(builder),{'home_affordance':'home','attachment_clear':'clear','buffer_image_blit':'blit'}[family],str(fmt),str(target),*map(str,shaders),str(payload),str(profile['midgard']['vert']['work_regs']),str(profile['midgard']['frag']['work_regs'])],check=True)
        data=payload.read_bytes()
        if len(data)!=0x40000:raise ValueError('wrong payload extent')
        want_bytes=expected(family,variant,target);oracle.write_bytes(want_bytes)
        if data[0x24000:0x24000+len(want_bytes)]==want_bytes:raise ValueError('oracle was CPU-initialized into GPU destination')
        immutable=[{'offset':0x1800,'bytes':0xc00},{'offset':0x3000,'bytes':0xc0},
                   {'offset':0x20000,'bytes':4096},{'offset':0x22000,'bytes':4096},
                   {'offset':0x24000+len(want_bytes),'bytes':0x28000-0x24000-len(want_bytes)},
                   {'offset':0x28000,'bytes':0x18000}]
        result['cases'].append({'name':name,'payload':str(payload),
            'logical_target':target,'full_air_output_targets':want,
            'execution':profile['execution'],'outputs':[{'name':'rt'+str(target),
                'offset':0x24000,'bytes':len(want_bytes),'expected':str(oracle),
                'expected_sha256':hashlib.sha256(want_bytes).hexdigest(),
                'element_bytes':2 if fmt==2 else 1,'tolerance':0 if fmt==2 or family=='attachment_clear' else 1}],
            'immutable':immutable,'payload_sha256':hashlib.sha256(data).hexdigest(),
            'pixel_oracle':'independent actual AIR arithmetic; blit byte mask vertical flip; home source->luma->lookup2; clear zeros',
            'format':profile['output_color_format']})
    (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'manifest':str(out/'manifest.json'),'cases':len(result['cases'])}))

if __name__=='__main__':main()
