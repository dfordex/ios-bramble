#!/usr/bin/env python3
"""Build private executable GPU fixtures and independent pixel oracles.

The shader input manifest comes from translate_blur.py. RGBA16Float needs an
additional reviewed native fragment packing receipt; its BGRA-native shader
cannot be reused merely by changing framebuffer writeback format.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
FRAGMENTS = ['downsample_8_frag_lph'] + [f'narrow_blur_{n}_frag_lph' for n in (7,11,15,19,23,27)] + ['single_pass_blur_3_lph']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiled',required=True,type=Path)
    parser.add_argument('--mesa-build',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--rgba16-receipt',type=Path)
    args=parser.parse_args()
    build=args.mesa_build.resolve();source=build.parent/'mesa-26.2.4'
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    compiler=out/'build-blur-suite'
    command=['clang','-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-unused-parameter']
    for include in (build/'src/panfrost',source/'src/panfrost',build/'src',source/'src',build/'include',source/'include'):
        command+=['-I'+str(include)]
    subprocess.run(command+[str(HERE/'build_blur_suite.c'),'-o',str(compiler)],check=True)
    compiled=args.compiled.resolve();manifest=json.loads(compiled.read_text())
    result={'cases':[],'blocked':[],'gpu_va':0x02000000,'private_bytes':0x40000,
            'required_shader_present':3,'max_shader_core_id_range':4,
            'fixture_source_sha256':sha(HERE/'build_blur_suite.c'),
            'compiled_manifest_sha256':sha(compiled),'device_execution_verified':False}
    for pair in manifest['pairs']:
        rgba=pair['attachment_format']=='RGBA16Float'
        kind=FRAGMENTS.index(pair['fragment'])
        name=pair['fragment']+('_rgba16f' if rgba else '_bgra8')
        directory=compiled.parent/(pair['fragment']+('_RGBA16Float' if rgba else ''))
        vs=directory/'pair.vert.midgard';fs=directory/'pair.frag.midgard'
        fsinfo=pair['frag_midgard'];vsinfo=pair['vert_midgard']
        if rgba and not pair.get('native_packing_verified', False):
            if not args.rgba16_receipt:
                result['blocked'].append({'name':name,'reason':'RGBA16Float requires actual native raw64 fragment packing; compile-only BGRA bytes are insufficient'})
                continue
            receipt=json.loads(args.rgba16_receipt.read_text())
            if receipt['output_format']!='RGBA16Float' or receipt['fragment']!=pair['fragment'] or not receipt['native_packing_verified']:
                raise ValueError('RGBA16 native output-packing receipt does not match the actual shader')
            fs=Path(receipt['artifact']).resolve();fsinfo=receipt
        if sha(vs)!=vsinfo['sha256'] or sha(fs)!=fsinfo['sha256']:
            raise ValueError('native shader digest mismatch')
        case=out/name;case.mkdir(exist_ok=True)
        payload=case/'payload.bin';expected=case/'expected.bin'
        def fnv(path):
            h=0xcbf29ce484222325
            for b in path.read_bytes():h=((h^b)*0x100000001b3)&0xffffffffffffffff
            return hex(h)
        command=[str(compiler),str(vs),str(fs),str(payload),str(expected),str(kind),str(int(rgba)),
                 str(fsinfo['bytes']),str(fsinfo['work_regs']),str(fsinfo['tls']),fnv(vs),fnv(fs)]
        r=subprocess.run(command,capture_output=True,text=True)
        (case/'builder.log').write_text(r.stdout+r.stderr)
        if r.returncode or 'packed_readback=PASS' not in r.stdout:
            raise RuntimeError(f'fixture pack validation failed: {name}: {r.stderr}')
        n=8192 if rgba else 4096
        immutable=[{'offset':0xa000,'bytes':0x4000},{'offset':0x20000,'bytes':0x20000}]
        if n<8192:immutable.append({'offset':0xe000+n,'bytes':8192-n})
        result['cases'].append({'name':name,'payload':str(payload),'size':payload.stat().st_size,
            'payload_sha256':sha(payload),'outputs':[{'name':'pixels','offset':0xe000,'bytes':n,
            'expected':str(expected),'element_bytes':2 if rgba else 1,'tolerance':1}],
            'immutable':immutable,'pixel_stride':8 if rgba else 4,'width':32,'height':32,
            'tls_per_thread':fsinfo['tls'],'tls_allocation_offset':0x10000,'tls_allocation_bytes':0x10000,
            'max_shader_core_id_range':4,'shader_vertex_sha256':sha(vs),'shader_fragment_sha256':sha(fs),
            'oracle':'actual AIR tap arithmetic; nonconstant binaryRGBA stripes; nonzero dyadic weights/offsets; EDR=.5',
            'expected_sha256':sha(expected)})
    (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'cases':len(result['cases']),'blocked':result['blocked'],'manifest':str(out/'manifest.json')},indent=2))


if __name__=='__main__':
    main()
