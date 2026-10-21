#!/usr/bin/env python3
"""Reproduce actual QC path/stroke compilation; private inputs/outputs stay external."""
import argparse, concurrent.futures, hashlib, json, os, pathlib, re, subprocess
PAIRS=[('path_blit','path_blit_vert_lph','path_blit_frag_lph','BGRA8Unorm',152,8),('path_cubic','path_cubic_vert_0_lph','path_cubic_frag_lph','BGRA8Unorm',153,16),('path_rect','path_rect_vert_lph','path_rect_frag_lph','BGRA8Unorm',263,16),('stroke_line','stroke_line_vert_lph','stroke_line_frag_lph','RGBA16Float',283,24)]
PACKING={'layouts':{'1':{'stride':48,'step_function':'PerVertex','step_rate':1}},'attributes':{str(i):{'format':f,'offset':o,'buffer_index':1} for i,f,o in [(0,'Float4',0),(1,'Float2',16),(2,'Float2',24),(3,'Half4',32)]}}
def digest(p):return {'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def fnv(p):
    v=0xcbf29ce484222325
    for b in p.read_bytes():v=((v^b)*0x100000001b3)&0xffffffffffffffff
    return f'{v:016x}'
def main():
    p=argparse.ArgumentParser();p.add_argument('--metallib',required=True);p.add_argument('--translator',required=True);p.add_argument('--validator',required=True);p.add_argument('--profile',required=True);p.add_argument('--compiler',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True);vdesc=out/'vertex-packing0.json';vdesc.write_text(json.dumps(PACKING,indent=2)+'\n')
    native_profile=json.loads(pathlib.Path(a.profile).read_text())
    native_cap=native_profile['capabilities']['vulkan10requirements']
    native_cap.setdefault('extensions',{})['VK_EXT_rasterization_order_attachment_access']=1
    native_cap['features']['VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT']={'rasterizationOrderColorAttachmentAccess':True}
    native_profile['provenance']['rule']='Native ordered tilebuffer adapter only. No Vulkan runtime support claim. Requires actual ordered memoryless R32Float attachment2, clear0, storeDontCare and native MRT state.'
    native_path=out/'native-ordered-fetch-profile.json';native_path.write_text(json.dumps(native_profile,indent=2)+'\n')
    def run(pair):
        name,vs,fs,fmt,row,aux=pair;record={'pair':name,'vertex':vs,'fragment':fs,'row':row,'attachment_format':fmt,'runtime_tested':False}
        cmd=[a.translator,a.metallib,str(out/(name+'.spv')),'--function',vs,'--fragment',fs,'--profile',a.profile,'--vertex-descriptor',str(vdesc),'--color-format','0:'+fmt,'--color-format','1:'+fmt,'--color-format','2:R32Float','--no-timeout','--emit-meta',str(out/(name+'-meta.json'))]
        with (out/(name+'-translation.log')).open('w') as log:
            result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'METAL2VULKAN_SPIRV_VAL':a.validator})
        if result.returncode:
            floor_error=(out/(name+'-translation.log')).read_text().strip()
            if name!='path_blit':
                record.update(status='failed_air_translation',exit_code=result.returncode,reason=floor_error);return record
            record['vulkan_floor_rejection']=floor_error
            record['native_ordered_tilebuffer_contract']={'formats':['BGRA8Unorm','BGRA8Unorm','R32Float'],'attachment2':{'storage':'memoryless','load_action':'clear','clear_color':[0,0,0,0],'store_action':'dontcare','ordered_read_modify_write':True},'vulkan_runtime_support_claim':False}
            cmd[cmd.index('--profile')+1]=str(native_path)
            with (out/(name+'-native-translation.log')).open('w') as log:
                result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'METAL2VULKAN_SPIRV_VAL':a.validator})
            if result.returncode:
                record.update(status='failed_native_translation',exit_code=result.returncode,reason=(out/(name+'-native-translation.log')).read_text().strip());return record
        meta=json.loads((out/(name+'-meta.json')).read_text());record['reflection']=meta;record['spirv']={s:digest(out/(name+'.'+s+'.spv')) for s in ['vert','frag']}
        # These three real translated families are storage-pulled. No dummy vertex input is substituted.
        if meta['vertex_input']['attributes'] or meta['vertex_input']['bindings']:
            record.update(status='rejected_unexpected_vertex_interface');return record
        cmd=[a.compiler,str(out/(name+'.vert.spv')),str(out/(name+'.frag.spv')),str(out/(name+'.vert.midgard')),str(out/(name+'.frag.midgard')),fnv(out/(name+'.vert.spv')),fnv(out/(name+'.frag.spv')),str(aux)]
        with (out/(name+'-midgard.log')).open('w') as log:result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
        record.update(status='failed_midgard' if result.returncode else ('compiled_native_ordered_fetch' if name=='path_blit' else 'compiled'),exit_code=result.returncode)
        if not result.returncode:
            record['midgard']={s:digest(out/(name+'.'+s+'.midgard')) for s in ['vert','frag']}
            record['info']=re.findall(r'.*Midgard bytes=.*',(out/(name+'-midgard.log')).read_text())
            if not record['midgard']['frag']['bytes']:record.update(status='compiled_empty_fragment',requires='Canonical no-FS renderer state plus actual early-Z/stencil/blend state; not a dummy fragment executable.')
            record['resource_abi']={'push_ubo':0,'ubo_binding_to_hardware':'N+1','storage_binding':0,'storage_record_offset':96,'storage_record_fields':['GPUVA:u64','bytes:u32','reserved:u32'],'uniform_windows':[64,aux],'viewport_scale_offset':512,'viewport_offset_offset':528,'raw_vertex_offset_offset':544,'base_instance_offset':552}
        return record
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run,PAIRS))
    manifest={'schema':1,'claim':'Actual host compiler output only; no GPU runtime or generic Metal coverage claim.','metallib':digest(pathlib.Path(a.metallib)),'compiler':digest(pathlib.Path(a.compiler)),'pairs':results}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('\n'.join(r['pair']+': '+r['status'] for r in results))
if __name__=='__main__':main()
