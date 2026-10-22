#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Emit a private authenticated Metal registry from actual local translations.

No Apple/AIR/SPIR-V/Midgard bytes are written into the source tree. The registry
contains native code and complete binding contracts. Selection is distinct from
kernel runtime support; full MRT profiles remain gated by the provider.
"""
import argparse
import hashlib
import copy
import importlib.util
import json
from pathlib import Path
import re

METALLIB_SHA = '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9'
FORMATS = {'BGRA8Unorm':80, 'RGBA16Float':115, 'R8Unorm':10}
VK_METAL = {44:80, 97:115, 9:10, 16:30, 100:55}
STAGE = {'Vertex':1, 'Fragment':2}
# Verified QC packing0 (no L token), including inactive declared attributes.
ATTRIBUTES = [[0,31,0,1], [1,29,16,1], [2,29,24,1], [3,27,32,1]]
# MTLVertexFormat Float4=31,Float2=29,Half4=27; PerVertex=1.
LAYOUTS = [[1,48,1,1]]
BLUR_NAMES = ['downsample_8_frag_lph']+[f'narrow_blur_{n}_frag_lph' for n in (7,11,15,19,23,27)]+['single_pass_blur_3_lph']
DS4_PINS = ['f5556b29f212c3674cb16b166a7dbf93671b4c27b7c65e54b78d77a2837f2be1',
            '1771f55d5bf91525734b33166e001bdf2b402e7467988c366016c8c1f8ff2a82']


def sha(data): return hashlib.sha256(data).hexdigest()
def fail(message): raise ValueError(message)
def name(value):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9_]{1,100}',value): fail('invalid bounded name')
    return value


def shader(path, info):
    data=path.read_bytes()
    if not 0<len(data)<=0x10000 or len(data)!=info['bytes'] or sha(data)!=info['sha256']:
        fail(f'changed native shader: {path}')
    if not 1<=info['first_tag']<=15 or not 1<=info['work_regs']<=16 or info['tls'] not in (0,16,32,64) or info['wls']:
        fail('unsupported native shader resources')
    return {'path':str(path.resolve()), 'sha256':sha(data), 'bytes':len(data),
            'first_tag':info['first_tag'],'work_regs':info['work_regs'],'tls':info['tls'],'wls':0}


def contract(meta, blur=False):
    """Keep actual descriptor bindings, readonly windows and push offsets."""
    interface=meta['interface'] if 'interface' in meta else meta['resources']
    slots={(s['stage'],s['class'],s['index']):r for s,r in interface['slots']}
    pushes=[]; bind_push={}
    rules=dict(meta.get('graphics',{}).get('color_write_rules',[]))
    for group in interface['push']:
        stage=STAGE[group['stage']]
        for field in group['fields']:
            off=field['loc']['Push']['offset']; size=field['size']
            if size!=4 or off<0 or off+size>560: fail('unsupported push field')
            if 'SlotBindOffset' in field['field']:
                slot=field['field']['SlotBindOffset'];key=(slot['stage'],slot['class'],slot['index'])
                bind_push[key]=off;pushes.append([stage,1,slot['index'],off,4,0])
            elif 'ColorWriteRule' in field['field']:
                target=field['field']['ColorWriteRule']
                if target not in rules: fail('missing actual color write rule')
                pushes.append([stage,2,target,off,4,rules[target]])
            else:fail('unknown push semantic')
    resources=[]; texture_count={1:0,2:0}
    for group in meta['layout']['sets']:
        if group['set']!=0:fail('only descriptor set0 supported')
        for b in group['bindings']:
            if b['count']!=1 or b.get('flags',0):fail('descriptor array or flags unsupported')
            src=b['source'];binding=b['binding']
            if 'Buffer' in src:
                slot=src['Buffer'];key=(slot['stage'],'Buffer',slot['index']);r=slots[key]['Buffer']
                access=r['access']; flags=int(access['read'])+2*int(access['write'])
                if not flags or flags&2:fail('writable shader buffer unsupported')
                window=r['window'];form=r['form']['Descriptor'];stage=STAGE[slot['stage']]
                if form=='Storage' and window=='Whole': flags|=4;start=size=0;sysval=96+16*binding
                elif form=='UniformWords' and 'Bounded' in window:
                    start=window['Bounded']['start'];size=window['Bounded']['len'];sysval=0
                else:fail('unreviewed buffer view')
                resources.append([stage,1,slot['index'],binding,binding+1,flags,start,size,sysval,bind_push[key]])
            elif 'CombinedTextureSampler' in src:
                c=src['CombinedTextureSampler'];t=c['texture'];stage=STAGE[t['stage']];native=texture_count[stage];texture_count[stage]+=1
                if c['sampler']['compare'] or c['sampler']['integer'] or c['sampler']['raw']:fail('unsupported sampler semantic')
                sm=c['sampler']['sampler'];imm=b['immutable_sampler'];constant='Constexpr' in sm
                if constant != bool(imm):fail('ambiguous sampler binding')
                # Constexpr state is carried as a private metadata receipt too;
                # providers must synthesize it, never require caller slot0.
                sampler_index=sm['Slot'] if not constant else native
                resources.append([stage,2,t['index'],binding,native,1,0,0,0 if blur else 352+32*native,0])
                resources.append([stage,3,sampler_index,binding,native,1|(8 if constant else 0),0,0,0,0])
            elif 'InputAttachment' in src:
                resources.append([2,4,src['InputAttachment'],binding,src['InputAttachment'],1,0,0,0,0])
            else:fail('unknown descriptor source')
    if len(resources)>16 or len(pushes)>32:fail('contract exceeds provider bounds')
    return resources,pushes


def blur_profiles(path, ds4):
    result=[];j=json.loads(path.read_text())
    if j['metallib_sha256']!=METALLIB_SHA:fail('changed QuartzCore identity')
    pairs=j['pairs']
    for pair in pairs:
        if pair['status']!='compiled' or pair['air_function_constants'] is not None:fail('uncompiled or specialized blur profile')
        fragment=name(pair['fragment']);rgba=pair['attachment_format']=='RGBA16Float'
        identifier=108 if rgba else 100+BLUR_NAMES.index(fragment)
        if rgba and (fragment!='narrow_blur_23_frag_lph' or not pair.get('native_packing_verified')):fail('unverified native raw64 packing')
        directory=path.parent/(fragment+('_RGBA16Float' if rgba else ''))
        meta=json.loads((directory/'meta.json').read_text())
        recipe=Path(__file__).resolve().parents[1]/'userland/a5xelte-air-translation/families/translate_blur.py'
        spec=importlib.util.spec_from_file_location('registry_blur_contract',recipe)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        core=module.load_contract();expected=copy.deepcopy(core.PAIRS['downsample_4'])
        expected['buffer_windows'][2]=('UniformWords',32 if fragment=='downsample_8_frag_lph' else 82)
        checked=module.check_attachment_meta(meta,expected,pair['attachment_format'],core)
        if json.loads(json.dumps(checked))!=pair['io_abi']:fail('metadata no longer matches the compiler contract receipt')
        resources,pushes=contract(meta,True)
        if pair['io_abi']['resource_slots'] != [['Vertex','Buffer',2],['Vertex','Buffer',3],['Fragment','Buffer',1],['Fragment','Buffer',6],['Fragment','Texture',3],['Fragment','Sampler',0]]:fail('changed blur interface')
        vs=shader(directory/'pair.vert.midgard',pair['vert_midgard']);fs=shader(directory/'pair.frag.midgard',pair['frag_midgard'])
        result.append({'id':identifier,'name':fragment+('_rgba16f' if rgba else '_bgra8'),'vertex':pair['vertex'],'fragment':fragment,
            'formats':[FORMATS[pair['attachment_format']]],'flags':1|2|4|(0 if rgba else 16),'viewport':[1080,1920],
            'resources':resources,'push':pushes,'attributes':ATTRIBUTES,'layouts':LAYOUTS,
            'passes':[{'id':identifier,'target':0,'vertex':vs,'fragment':fs}]})
    if ds4:
        if len(ds4)!=2:fail('both genuine DS4 stages required')
        template=next(p for p in result if p['id']==100)
        p=json.loads(json.dumps(template));p.update(id=99,name='downsample_4_frag_lph_bgra8',fragment='downsample_4_frag_lph')
        p['resources'][2][7]=72
        p['passes']=[{'id':99,'target':0,'vertex':shader(ds4[0],{'bytes':2048,'sha256':DS4_PINS[0],'first_tag':5,'work_regs':8,'tls':0,'wls':0}),
            'fragment':shader(ds4[1],{'bytes':3472,'sha256':DS4_PINS[1],'first_tag':5,'work_regs':7,'tls':0,'wls':0})}]
        result.insert(0,p)
    return result


def misc_profiles(path):
    j=json.loads(path.read_text());result={}
    if j['metallib_sha256']!=METALLIB_SHA:fail('changed QuartzCore identity')
    for index,pair in enumerate(j['profiles']):
        if index>=9 or pair['status']!='compiled':fail('unreviewed misc manifest')
        family=name(pair['family']);variant=name(pair['variant']);target=pair['render_target'];pid=200+index
        key=(family,variant);prefix=path.parent/(family+'_'+variant+'_rt'+str(target))
        meta={'resources':pair['resources'],'layout':pair['layout'],'graphics':pair['graphics']}
        resources,pushes=contract(meta)
        native={'id':pid,'target':target,
            'vertex':shader(Path(str(prefix)+'.vert.midgard'),pair['midgard']['vert']),
            'fragment':shader(Path(str(prefix)+'.frag.midgard'),pair['midgard']['frag'])}
        if key not in result:
            formats=[VK_METAL[x['format']] for x in pair['graphics']['color_attachments']]
            result[key]={'id':pid,'name':family+'_'+variant,'vertex':pair['vertex'],'fragment':pair['fragment'],
                'formats':formats,'flags':(8 if pair['execution']=='single_SFBD_target_replay' else 0)|(16 if pid in (200,202) else 0),'viewport':[0,0],
                'resources':resources,'push':pushes,'attributes':ATTRIBUTES,'layouts':LAYOUTS,'passes':[]}
        profile=result[key]
        if profile['resources']!=resources or profile['push']!=pushes:fail('MRT replay resource contracts differ')
        profile['passes'].append(native)
    return list(result.values())


def path_profiles(path):
    j=json.loads(path.read_text())
    if j['metallib']['sha256']!=METALLIB_SHA:fail('changed QuartzCore identity')
    result=[]
    ids={'path_blit':400,'path_cubic':401,'path_rect':402,'stroke_line':403}
    for pair in j['pairs']:
        if pair['pair'] not in ids or pair['status'] not in ('compiled','compiled_native_ordered_fetch'):
            fail('unreviewed original path program')
        pid=ids[pair['pair']];meta=pair['reflection'];resources,pushes=contract(meta)
        stage_info={}
        for stage,line in zip(('vert','frag'),pair['info']):
            info=dict(pair['midgard'][stage])
            for source,dest in [('first_tag','first_tag'),('work_regs','work_regs'),('tls','tls'),('wls','wls')]:
                match=re.search(r'\b'+source+r'=(\d+)',line)
                if not match:fail('native compiler receipt missing')
                info[dest]=int(match.group(1))
            stage_info[stage]=shader(path.parent/(pair['pair']+'.'+stage+'.midgard'),info)
        result.append({'id':pid,'name':pair['pair']+'_original_mrt','vertex':pair['vertex'],'fragment':pair['fragment'],
            'formats':[VK_METAL[x['format']] for x in meta['graphics']['color_attachments']],
            'flags':32,'viewport':[0,0],'resources':resources,'push':pushes,'attributes':ATTRIBUTES,'layouts':LAYOUTS,
            'passes':[{'id':pid,'target':2,'vertex':stage_info['vert'],'fragment':stage_info['frag']}],
            'limitation':'Host-compiled original MRT or ordered-fetch program only; not executable on the native SFBD runtime.'})
    return result


def runtime_path_profiles(path, original_path):
    j=json.loads(path.read_text());originals=json.loads(original_path.read_text())
    if j['metallib_sha256']!=METALLIB_SHA:fail('changed path source identity')
    result=[]
    for record in j['programs']:
        kind=record['name'];pid={'path_rect':300,'path_cubic':301,'stroke_line':302}[kind]
        original=next(p for p in originals['pairs'] if p['pair']==kind)
        if any(record['original_spirv'][stage]!=original['spirv'][stage]['sha256'] for stage in ('vert','frag')):fail('runtime path program source changed')
        meta=original['reflection'];resources,pushes=contract(meta)
        vs=shader(Path(record['stages']['vert']['path']),record['stages']['vert'])
        fs=shader(Path(record['stages']['frag']['path']),record['stages']['frag'])
        passes=[{'id':pid,'target':0 if pid==302 else 2,'vertex':vs,'fragment':fs}]
        result.append({'id':pid,'name':kind+'_runtime_blend','vertex':original['vertex'],'fragment':original['fragment'],
          'formats':[VK_METAL[x['format']] for x in meta['graphics']['color_attachments']],
          'flags':128 if pid==302 else 64,'viewport':[0,0],'resources':resources,'push':pushes,
          'attributes':ATTRIBUTES if pid==302 else [],'layouts':LAYOUTS if pid==302 else [],'passes':passes})
    return result


def apply_blur_runtime(profiles, path, original):
    j=json.loads(path.read_text())
    if j['source_manifest_sha256']!=sha(original.read_bytes()) or j['profile_ids']!=list(range(99,109)):
        fail('runtime blur source/profile identity changed')
    if j['viewport_sysval']!={'stage':'Vertex','ubo':0,'scale_offset':512,'offset_offset':528,'record_bytes':16,'ubo_bytes':576} or j['base_vertex']!=0:
        fail('unreviewed viewport contract')
    programs=j['pairs']
    if len(programs)!=9:fail('runtime blur coverage incomplete')
    vertices=set()
    for entry in programs:
        if entry['vert_spirv_sha256']!='218bd3c9428002ed2c74b907f9b4296de35fbdc306608b7ab1d51ac140bcbbe6':fail('changed actual blur vertex AIR translation')
        vertices.add(entry['vert_midgard']['sha256'])
    if len(vertices)!=1:fail('runtime blur vertex contracts differ')
    for p in profiles:
        if not 99<=p['id']<=108:continue
        entries=[e for e in programs if e['fragment']==p['fragment'] and FORMATS[e['attachment_format']]==p['formats'][0]]
        entry=entries[0] if entries else programs[0] if p['id']==99 else None
        if entry is None:fail('runtime blur profile missing')
        if p['id']!=99 and entry['frag_midgard']['sha256']!=p['passes'][0]['fragment']['sha256']:fail('runtime blur unexpectedly changed fragment')
        p['passes'][0]['vertex']=shader(Path(entry['vert_midgard']['path']),entry['vert_midgard'])
        p['flags'] &= ~1
        p['viewport']=[0,0]
def apply_raw204_runtime(profiles, path, original):
    j=json.loads(path.read_text());source=json.loads(original.read_text())
    if j['profile_id']!=204 or j['logical_target']!=0 or j['sample_count']!=1 or j['operation']!='premultiplied_source_over_RGBA16Float' or j['metallib_sha256']!=METALLIB_SHA or j['source_manifest_sha256']!=sha(original.read_bytes()):fail('unreviewed RAW204 runtime contract')
    old=next(p for p in source['profiles'] if p['family']=='buffer_image_blit' and p['variant']=='rgba16f' and p['render_target']==0)
    if any(j['original_spirv'][s]!=old['spirv'][s]['sha256'] for s in ('vert','frag')):fail('RAW204 source SPIR-V differs')
    p=next(p for p in profiles if p['id']==204);vs=shader(Path(j['stages']['vert']['path']),j['stages']['vert'])
    if vs['sha256']!=p['passes'][0]['vertex']['sha256']:fail('RAW204 vertex changed')
    p['passes'][0]['fragment']=shader(Path(j['stages']['frag']['path']),j['stages']['frag'])
    p['flags'] |= 256

def apply_actual_qc_contracts(profiles, image_path):
    """UUID/opcode-guarded actual attachment creation, not SPIR-V outputs.

    Shader reflection describes emitted values. Metal write masks and inactive
    formats are separate and are reconstructed from this exact stock QC path.
    """
    tool=Path(__file__).with_name('a5mali-quartzcore-coverage.py')
    spec=importlib.util.spec_from_file_location('registry_qc_contract',tool)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    image=m.Image(image_path);rows=m.audit(image)['direct_fast_profiles']
    import struct
    # Zero Spec, S(default0) setter, write-mask selected-index test, coverage
    # override and format conversion are tied to the audited stock instructions.
    guards={0x18847f3ec:0xa9337fbf,0x18847f3f0:0xf81403bf,
      0x18838179c:0x7840d308,0x1883817a0:0x371000e8,
      0x1883817a4:0x12000508,0x1883817b8:0x94093852,
      0x188381834:0x528003c2,0x188381988:0xaa1903e0,
      0x1883819a8:0x94092fd6,0x1883819cc:0x94092fcd,
      0x1883819e4:0x52800102,0x1883819f0:0x52800022,
      0x188381a00:0x94093610,0x188381a0c:0x94093135,
      0x188487648:0x7840d008,0x18848764c:0x33000428}
    for addr,word in guards.items():
        if image.u32(image.offset(addr,4))!=word:fail('QC attachment instruction changed')
    # The actual named blend decoder maps sov to1; its native table decodes
    # RGB/alpha Add, sourceOne,destinationOneMinusSourceAlpha.
    blend_index=next((i for i in range(55) if image.string(image.pointer(0x1d5b461e8+i*8))=='sov'),None)
    if blend_index is None:fail('stock source-over decoder absent')
    blend=struct.unpack_from('<H',image.data,image.offset(0x188564fc2+2*blend_index,2))[0]
    if ((blend>>5)&7,(blend>>8)&15,(blend>>12)&15)!=(0,1,5):fail('stock source-over factors changed')
    for p in profiles:
        candidates=[r for r in rows if r['vertex']==p['vertex'] and r['fragment']==p['fragment'] and r['metal_pixel_format']==p['formats'][0]]
        if not candidates:fail('no actual QC row for compiled pair')
        contracts=[];formats=None;proof=[]
        for row in candidates:
            token=row['pipeline'];parts=token.split('_');frag=parts[1]
            count=int(re.search(r'A([123])',frag).group(1));selected=int(re.search(r'S([01])',frag).group(1)) if re.search(r'S([01])',frag) else 0
            color=p['formats'][0];second=30 if color==10 else color
            fmt=[color]+([second] if count>=2 else [])+([55 if 'w' in parts[0].split('X')[-1] else second] if count==3 else [])
            fmt += [0]*(8-len(fmt))
            if formats is not None and formats!=fmt:fail('actual same-profile formats disagree')
            formats=fmt
            # Metal descriptor defaults apply even to unconfigured format0 slots.
            states=[[15,0,0,0,1,0,1,0] for _ in range(8)]
            for i in range(count):states[i][0]=15 if i==selected else 0
            if 'Bsov' in parts[0]:states[selected]=[states[selected][0],1,0,0,1,5,1,5]
            if row['texture_index'] in (70,72):
                states[0][0]=states[1][0]=0;states[0][1]=states[1][1]=0
                states[2][0]=8;states[2][1]=1;states[2][2]=0;states[2][4]=states[2][5]=1
            elif row['texture_index'] in (79,80):
                states[2][0]=8;states[2][1]=0
                states[1 if selected==0 else 0][0]=0;states[1 if selected==0 else 0][1]=0
            if states not in contracts:contracts.append(states)
            proof.append({'row':row['row'],'pipeline':token,'selected_attachment':selected})
        p['formats']=formats;p['attachment_contracts']=contracts;p['qc_rows']=proof
        active={i for c in contracts for i,a in enumerate(c) if formats[i] and a[0]}
        if not p['flags']&32:
            p['passes']=[q for q in p['passes'] if q['target'] in active]
            if not p['passes'] or {q['target'] for q in p['passes']}!=active:fail('compiled pass coverage differs from actual active attachment')
            p['flags'] &= ~8
        if any(c[0][1] for c in contracts):p['flags'] |= 16
        else:p['flags'] &= ~16
    return {'uuid':m.EXPECTED_UUID,'image_sha256':sha(Path(image_path).read_bytes()),'source_over_decoder_index':blend_index}

def array(symbol,data):
    return 'static const uint8_t '+symbol+'[] = {\n'+''.join('  '+','.join(f'0x{x:02x}' for x in data[i:i+24])+',\n' for i in range(0,len(data),24))+'};\n'


def generic_profile(receipt_path, capture_path, metallib_path):
    recipe=Path(__file__).resolve().parents[1]/'userland/a5xelte-air-translation/generic/compile_0185.py'
    spec=importlib.util.spec_from_file_location('generic_recipe',recipe)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    j=module.validate_receipt(receipt_path,capture_path,metallib_path)
    if j['metallib_sha256']!=METALLIB_SHA:fail('unreviewed generic library')
    fragment=j['compiled_function']
    pid={'fixed_frag_lph_cpf':600,'fixed_frag_lph_cph':601}.get(fragment)
    if pid is None:fail('unreviewed generic precision variant')
    passes={}
    for key,stage in [('vertex','vert'),('fragment','frag')]:
        r=j['stages'][stage];info=r['native_info']
        expected={'vert':(1808,5,8,0,0,2,2),'frag':(848,5,6,0,0,0,3)}[stage]
        actual=tuple(info[k] for k in ('bytes','first_tag','work_regs','tls','wls','attributes','ubos'))
        if actual!=expected or info['textures'] or info['samplers']:fail('generic native ABI changed')
        passes[key]=shader(receipt_path.parent/(stage+'.midgard'),
            dict(bytes=r['midgard_bytes'],sha256=r['midgard_sha256'],
                first_tag=info['first_tag'],work_regs=info['work_regs'],tls=info['tls'],wls=info['wls']))
    # This is a narrow supported API contract for a genuine host-compiled pair,
    # not a reconstruction of the still-unobserved live vertex/target state.
    p={'id':pid,'name':fragment+'_bgra8','vertex':'std_vert0_lph',
       'fragment':fragment,'formats':[80]+[0]*7,'flags':0,'viewport':[0,0],
       'resources':[[1,1,2,0,1,1,0,64,0,0]],
       'push':[[1,1,2,0,4,0],[2,2,0,68,4,0x2222]],
       'attributes':ATTRIBUTES,'layouts':LAYOUTS,
       'passes':[dict(id=pid,target=0,**passes)],
       'attachment_contracts':[[[15,0,0,0,1,0,1,0] for _ in range(8)]],
       'function_constants':j['captured_constants'],
       'proof':'Exact typed fragment specialization and pinned host compilation; live pair not yet verified'}
    return p


def emit(profiles,output):
    if not profiles or len(profiles)>32:fail('registry profile count invalid')
    lines=['/* Generated private compiler outputs. Never commit. */\n'];rows=[];seen=set();blobs={}
    for p in profiles:
        if p['id'] in seen:fail('duplicate profile ID')
        seen.add(p['id']);prefix='a5compiled_'+str(p['id']);passes=[]
        for entry in p['passes']:
            stages=[]
            for stage in ('vertex','fragment'):
                info=entry[stage];data=Path(info['path']).read_bytes()
                if sha(data)!=info['sha256']:fail('native bytes changed during emission')
                if info['sha256'] not in blobs:
                    symbol='a5shader_'+info['sha256'];blobs[info['sha256']]=symbol;lines.append(array(symbol,data))
                stages.append('{'+','.join([blobs[info['sha256']],str(info['bytes']),str(info['first_tag']),str(info['work_regs']),str(info['tls']),str(info['wls']),json.dumps(info['sha256'])])+'}')
            passes.append('{'+f'{entry["id"]},{entry["target"]},'+','.join(stages)+'}')
        lines.append('static const A5MaliCompiledPass '+prefix+'_passes[] = {'+','.join(passes)+'};\n')
        for field,ctype in [('resources','A5MaliCompiledResource'),('push','A5MaliCompiledPushField'),('attributes','A5MaliCompiledVertexAttribute'),('layouts','A5MaliCompiledVertexLayout')]:
            if p[field]:lines.append('static const '+ctype+' '+prefix+'_'+field+'[] = {'+','.join('{'+','.join(map(str,v))+'}' for v in p[field])+'};\n')
        contracts=prefix+'_attachment_contracts'
        lines.append('static const A5MaliCompiledAttachmentContract '+contracts+'[] = {'+','.join('{ {'+','.join('{'+','.join(map(str,a))+'}' for a in c)+'} }' for c in p['attachment_contracts'])+'};\n')
        fmt=p['formats']+[0]*(8-len(p['formats']))
        values=[str(p['id']),json.dumps(name(p['name'])),json.dumps(name(p['vertex'])),json.dumps(name(p['fragment'])),'{'+','.join(map(str,fmt))+'}',str(p['flags']),*map(str,p['viewport']),prefix+'_passes',str(len(p['passes']))]
        for field in ('resources','push','attributes','layouts'):values += [prefix+'_'+field if p[field] else 'NULL',str(len(p[field]))]
        values += [contracts,str(len(p['attachment_contracts']))]
        rows.append('{'+','.join(values)+'}')
    lines.append('static const A5MaliCompiledProfile kA5MaliCompiledProfiles[] = {\n'+',\n'.join(rows)+'\n};\n')
    for p in profiles:
        constants=p.get('function_constants')
        if not constants:continue
        if p['id'] not in (600,601) or len(constants)!=58:fail('unreviewed specialized function profile')
        values=[]
        for key,item in sorted(constants.items()):
            raw=list(bytes.fromhex(item['raw']))
            width={49:1,51:3,53:1}.get(item['type'])
            if width!=len(raw) or raw!=item['values']:fail('invalid typed generic constant')
            values.append('{'+','.join([json.dumps(name(key)),str(item['type']),str(width),
                '{'+','.join(map(str,raw+[0]*(3-width)))+'}'])+'}')
        lines.append(f'#define A5_MALI_HAS_GENERIC_{p["id"]} 1\nstatic const A5MaliCompiledFunctionConstant kA5MaliProfile{p["id"]}Constants[] = {{\n'+',\n'.join(values)+'\n};\n')
    output.write_text(''.join(lines))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--blur-manifest',type=Path,required=True)
    p.add_argument('--misc-manifest',type=Path)
    p.add_argument('--blur-runtime-manifest',type=Path)
    p.add_argument('--path-manifest',type=Path)
    p.add_argument('--path-runtime-manifest',type=Path)
    p.add_argument('--raw204-runtime-manifest',type=Path)
    p.add_argument('--generic-receipt',type=Path)
    p.add_argument('--generic-capture',type=Path)
    p.add_argument('--generic-metallib',type=Path)
    p.add_argument('--generic-cph-receipt',type=Path)
    p.add_argument('--generic-cph-capture',type=Path)
    p.add_argument('--ds4-vertex',type=Path);p.add_argument('--ds4-fragment',type=Path)
    p.add_argument('--quartzcore-image',type=Path,required=True)
    p.add_argument('--output-dir',type=Path,required=True)
    a=p.parse_args();out=a.output_dir.resolve()
    source=Path(__file__).resolve().parents[1]
    if out==source or source in out.parents:fail('private generated data must remain outside Git source tree')
    if bool(a.ds4_vertex)!=bool(a.ds4_fragment):fail('both DS4 stages required')
    profiles=blur_profiles(a.blur_manifest.resolve(),[a.ds4_vertex,a.ds4_fragment] if a.ds4_vertex else None)
    if a.blur_runtime_manifest:apply_blur_runtime(profiles,a.blur_runtime_manifest.resolve(),a.blur_manifest.resolve())
    if a.misc_manifest:profiles+=misc_profiles(a.misc_manifest.resolve())
    if a.path_runtime_manifest:
        if not a.path_manifest:fail('original path manifest required')
        profiles+=runtime_path_profiles(a.path_runtime_manifest.resolve(),a.path_manifest.resolve())
    if a.path_manifest:profiles+=path_profiles(a.path_manifest.resolve())
    if a.raw204_runtime_manifest:
        if not a.misc_manifest:fail('RAW204 requires original misc source manifest')
        apply_raw204_runtime(profiles,a.raw204_runtime_manifest.resolve(),a.misc_manifest.resolve())
    else:
        for profile in profiles:
            if profile['id']==204:profile['flags'] |= 32
    qc=apply_actual_qc_contracts(profiles,a.quartzcore_image.resolve())
    if any((a.generic_receipt,a.generic_capture,a.generic_metallib)):
        if not all((a.generic_receipt,a.generic_capture,a.generic_metallib)):fail('generic recipe needs receipt, capture and actual library')
        profiles.append(generic_profile(a.generic_receipt.resolve(),a.generic_capture.resolve(),a.generic_metallib.resolve()))
    if any((a.generic_cph_receipt,a.generic_cph_capture)):
        if not all((a.generic_cph_receipt,a.generic_cph_capture,a.generic_metallib)):fail('CPH recipe needs receipt, capture and actual library')
        profiles.append(generic_profile(a.generic_cph_receipt.resolve(),a.generic_cph_capture.resolve(),a.generic_metallib.resolve()))
    out.mkdir(parents=True,exist_ok=True);include=out/'A5MaliCompiledRegistryData.inc';emit(profiles,include)
    receipt={'schema':2,'quartzcore_attachment_audit':qc,'metallib_sha256':METALLIB_SHA,'include_sha256':sha(include.read_bytes()),
             'generator_sha256':sha(Path(__file__).read_bytes()),
             'input_manifests':{str(path.resolve()):sha(path.read_bytes()) for path in (a.blur_manifest,a.blur_runtime_manifest,a.misc_manifest,a.path_manifest,a.path_runtime_manifest,a.raw204_runtime_manifest,a.generic_receipt,a.generic_capture,a.generic_cph_receipt,a.generic_cph_capture) if path},'profiles':profiles,
             'claim':'Authenticated native program and binding registry; pipeline/runtime acceptance is separately gated.'}
    (out/'compiled-registry.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'profiles':len(profiles),'native_passes':sum(len(x['passes']) for x in profiles),'include':str(include),'sha256':receipt['include_sha256']}))

if __name__=='__main__':main()
