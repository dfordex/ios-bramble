#!/usr/bin/env python3
"""Compile three real single-target portability variants and bounded phone fixtures.

Full original MRT profiles must first be built by translate_path.py. All shader,
payload, expected and mask bytes are private runtime artifacts, never Git inputs.
"""
import argparse,hashlib,json,pathlib,re,struct,subprocess

def fnv(p):
    h=0xcbf29ce484222325
    for x in p.read_bytes():h=((h^x)*0x100000001b3)&0xffffffffffffffff
    return f'{h:016x}'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    a=argparse.ArgumentParser();a.add_argument('--mesa-source',required=True);a.add_argument('--mesa-build',required=True);a.add_argument('--compiler',required=True);a.add_argument('--shaders',required=True);a.add_argument('--output',required=True);args=a.parse_args()
    src=pathlib.Path(args.mesa_source).resolve();build=pathlib.Path(args.mesa_build).resolve();shaders=pathlib.Path(args.shaders).resolve();out=pathlib.Path(args.output).resolve();out.mkdir(parents=True,exist_ok=True)
    builder=out/'build-path-suite';code=pathlib.Path(__file__).with_suffix('.c')
    cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-parameter']
    cmd += ['-I'+str(p) for p in [build/'src/panfrost',src/'src/panfrost',src/'src',src/'include',build/'include']]
    subprocess.run(cmd+[str(code),'-o',str(builder)],check=True)
    manifest={'schema':1,'claim':'Isolated actual-shader portability tests, not original MRT execution or general Metal support.','cases':[],'blocked':[{'name':'path_blit_original_MRT','reason':'T720/v4 supports one color target; original reads+writes R32Float RT2 and writes RT0/RT1. A valid general multipass rendergraph is not implemented.','source_evidence':['Mesa26.2.4 pan_props.h:105..108','pan_desc.c PAN_ARCH4 pan_emit_fbd assert(rt_count<=1)','Actual AIR path_blit_frag returns0toRT2 afterreadingd0.']}]}
    for name,kind,aux in [('path_rect','rect',16),('path_cubic','cubic',16),('stroke_line','stroke',24)]:
        vs=shaders/(name+'.vert.spv');fs=shaders/(name+'.frag.spv');vbin=out/(name+'.single.vert.midgard');fbin=out/(name+'.single.frag.midgard');log=out/(name+'-single-midgard.log')
        with log.open('w') as f:subprocess.run([args.compiler,str(vs),str(fs),str(vbin),str(fbin),fnv(vs),fnv(fs),str(aux),'single_target'],stdout=f,stderr=subprocess.STDOUT,check=True)
        info=re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+)',log.read_text());assert len(info)==2 and all(r[1]=='5' and r[4]=='0' and r[5]=='0' for r in info)
        payload=out/(name+'-payload.bin');subprocess.run([str(builder),kind,str(vbin),str(fbin),info[0][3],info[1][3],str(payload)],check=True)
        assert payload.stat().st_size==0x40000
        elem=2 if kind=='stroke' else 4;pixel_bytes=8 if kind=='stroke' else 4
        expected=bytearray(1024*pixel_bytes);mask=bytearray(len(expected));positive=0;negative=0
        for y in range(32):
            for x in range(32):
                far_out=x<6 or x>=26 or y<6 or y>=26
                if kind=='stroke':
                    inside=10<=x<22 and 14<=y<18
                    far_out=x<6 or x>=26 or y<10 or y>=22
                    val=struct.pack('<4H',0x3400,0x3800,0x3a00,0x3c00) if inside else bytes(8)
                    selected=inside or far_out
                else:
                    inside=10<=x<22 and 10<=y<22
                    positive_pixel=inside and (kind=='rect' or x+y>=36)
                    zero_pixel=far_out or (inside and kind=='cubic' and x+y<=28)
                    val=struct.pack('<I',0x3f800000 if positive_pixel else 0)
                    selected=positive_pixel or zero_pixel
                    inside=positive_pixel
                i=(y*32+x)*pixel_bytes;expected[i:i+pixel_bytes]=val
                if selected:mask[i:i+pixel_bytes]=bytes([255])*pixel_bytes;positive+=int(inside);negative+=int(not inside)
        assert positive>=16 and negative>=128
        exp=out/(name+'-expected.bin');msk=out/(name+'-mask.bin');exp.write_bytes(expected);msk.write_bytes(mask)
        transform='sole coverage outputRT2 -> SFBD R32FloatRT0' if kind!='stroke' else 'prove identical RGBA16FloatRT0/1 values after exact format specialization; collapse duplicateRT1; upstream native half packing'
        record={'name':name+'_single_target','payload':str(payload),'payload_sha256':sha(payload),'outputs':[{'name':'coverage' if kind!='stroke' else 'RGBA16Float','offset':0x20000,'bytes':len(expected),'expected':str(exp),'element_bytes':elem,'tolerance':0,'mask':str(msk),'expected_sha256':sha(exp),'mask_sha256':sha(msk)}],'immutable':[{'offset':0x4000,'bytes':0x4000},{'offset':0x10000,'bytes':0x5000},{'offset':0x30000,'bytes':0x1000}],'portability_transform':transform,'shader_sha256':{'vertex':sha(vbin),'fragment':sha(fbin)},'shader_bytes':{'vertex':vbin.stat().st_size,'fragment':fbin.stat().st_size},'oracle':{'positive_pixels':positive,'zero_pixels':negative,'masked_raster_edges':True,'definition':'rectNDC[-.5,.5]^2; cubicP(t)=(2t-.5,2t-.5), t[0,.5],baselineX.5; stroke(8,16)->(24,16),sidePad4,endPad0,color(.25,.5,.75,1)'},'gpu_va':0x02000000,'payload_bytes':0x40000,'heap':{'offset':0x24000,'bytes':0x4000},'guards':{'offset':0x30000,'bytes':0x1000},'runtime_verified':False}
        manifest['cases'].append(record)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(out/'manifest.json')
if __name__=='__main__':main()
