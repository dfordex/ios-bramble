#!/usr/bin/env python3
"""Privately translate/validate/compile authenticated QC misc warmup families.

Inputs and emitted AIR/SPIR-V/Midgard/logs stay outside the source checkout.
The summary is a source-only metadata manifest; no generated shader is Git data.
This host proof does not establish device resource binding or GPU execution.
"""
import argparse
import hashlib
import json
from pathlib import Path
import os
import re
import shlex
import subprocess

PACKING0 = {
    'layouts': {'1': {'stride': 48, 'step_function': 'PerVertex', 'step_rate': 1}},
    'attributes': {str(i): {'format': f, 'offset': o, 'buffer_index': 1}
                   for i, (f, o) in enumerate([
                       ('Float4', 0), ('Float2', 16), ('Float2', 24), ('Half4', 32)])},
}
# Original QC named functions and static warmup table rows; no function aliases.
FAMILIES = {
    'buffer_image_blit': ('buffer_image_blit_vert_lph', 'buffer_image_blit_frag_lph',
                          [('bgra8', 'BGRA8Unorm', [141]),
                           ('r8', 'R8Unorm', [264]),
                           ('rgba16f', 'RGBA16Float', [280])]),
    'home_affordance': ('std_vert1_lph', 'home_affordance_base_lph',
                         [('bgra8', 'BGRA8Unorm', [204])]),
    'attachment_clear': ('path_blit_vert_lph', 'attachment_clear_frag_lph',
                          [('bgra8', 'BGRA8Unorm', [166])]),
}

def run(command, log, cwd=None, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(result.stdout)
    return result.returncode


def fnv(data):
    value = 0xcbf29ce484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001b3) & ((1 << 64) - 1)
    return value


def build_config(meta, prefix, destination):
    bindings = meta['layout']['sets']
    if len(bindings) != 1 or bindings[0]['set'] != 0:
        raise ValueError('only actual set0 family bindings supported')
    slots = {(s['stage'], s['class'], s['index']): interface
             for s, interface in meta['interface']['slots']}
    lines, profiles = [], []
    for stage_index, stage in enumerate(('vert', 'frag')):
        stage_name = 'Vertex' if stage_index == 0 else 'Fragment'
        stage_mask = 1 if stage_index == 0 else 16
        resources, textures = [], []
        for binding in bindings[0]['bindings']:
            if not binding['stages'] & stage_mask:
                continue
            if binding['count'] != 1 or binding['flags']:
                raise ValueError('unhandled descriptor count or flags')
            index, ty = binding['binding'], binding['ty']
            if ty in (6, 7):
                source = binding['source']['Buffer']
                info = slots[(source['stage'], source['class'], source['index'])]['Buffer']
                if info['access'] != {'read': True, 'write': False}:
                    raise ValueError('unhandled writable buffer')
                kind = 'uniform' if ty == 6 else 'storage'
                resources.append((index, f'nir_descriptor_type_{kind}_buffer'))
            elif ty == 1:
                combined = binding['source']['CombinedTextureSampler']
                texture = combined['texture']
                info = slots[(texture['stage'], texture['class'], texture['index'])]['Texture']
                if info['texture_type'] != 'Type2D' or info['access'] != {
                        'sample': True, 'read': False, 'write': False}:
                    raise ValueError('unhandled sampled texture ABI')
                if binding['immutable_sampler'] is None:
                    raise ValueError('only actual constexpr combined samplers supported')
                textures.append((index, len(textures)))
            else:
                raise ValueError(f'unhandled actual descriptor type {ty}')
        specs = []
        for spec in meta['stages'][stage_index]['specialization']['constants']:
            slot = spec['key'].get('RangeAtBindOffset')
            if slot is None or spec['size'] != 4:
                raise ValueError('unexpected specialization key')
            resource = slots[(slot['stage'], slot['class'], slot['index'])]['Buffer']
            window = resource['window']
            if not isinstance(window, dict) or window['Bounded']['start'] != 0:
                raise ValueError('specialization must use actual bounded range')
            specs.append((spec['id'], window['Bounded']['len']))
        for name, ctype, values in (
                ('bindings', 'a5_resource_binding', resources),
                ('textures', 'a5_texture_binding', textures),
                ('spec', 'a5_spec_value', specs)):
            body = ','.join('{%s,%s}' % item for item in values) or '{0,0}'
            lines.append(f'static const struct {ctype} k{stage}_{name}[] = {{{body}}};')
        push_bytes = max((p['offset'] + p['size'] for p in meta['layout']['push_constants']
                          if p['stages'] & stage_mask), default=0)
        module = prefix.with_suffix(f'.{stage}.spv').read_bytes()
        profiles.append('{UINT64_C(0x%016x),k%s_bindings,%d,k%s_spec,%d,k%s_textures,%d,%d}' % (
            fnv(module), stage, len(resources), stage, len(specs), stage, len(textures), push_bytes))
    lines.append('static const struct a5_stage_profile kStages[] = {%s};' % ','.join(profiles))
    destination.write_text('\n'.join(lines) + '\n')


def compile_backend(mesa, config, binary, log, target=0, raw16=False):
    source = Path(__file__).with_name('misc_backend.c').resolve()
    commands = subprocess.check_output(['ninja', '-t', 'commands',
        'src/panfrost/a5_t720_copy_shader'], cwd=mesa, text=True).splitlines()
    line = next(c for c in commands if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in c)
    cc = shlex.split(line)
    cc += ['-Werror', f'-DA5_FAMILY_CONFIG="{config}"',
           f'-DA5_SELECTED_RT={target}', f'-DA5_NATIVE_RGBA16={int(raw16)}']
    cc[cc.index('-c') + 1] = str(source)
    obj = binary.with_suffix('.o')
    cc[cc.index('-o') + 1] = str(obj)
    for flag in ('-MD', '-MQ', '-MF'):
        if flag in cc:
            i = cc.index(flag)
            del cc[i:i + (1 if flag == '-MD' else 2)]
    code = run(cc, log, cwd=mesa)
    if code:
        return code
    ld = shlex.split(commands[-1])
    ld[ld.index('-o') + 1] = str(binary)
    ld[ld.index('src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o')] = str(obj)
    ld.insert(ld.index('src/compiler/nir/libnir.a'), 'src/compiler/spirv/libvtn.a')
    return run(ld, log.with_name(log.stem + '-link.log'), cwd=mesa)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('metallib', 'translator', 'validator', 'profile', 'mesa-build', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--family', choices=FAMILIES, action='append')
    args = parser.parse_args()
    out = args.output.resolve()
    source_root = Path(__file__).resolve().parents[1]
    if out == source_root or source_root in out.parents:
        parser.error('generated proprietary outputs must be outside the source tree')
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        parser.error('--output must be empty so stale binaries cannot count as new compilation')
    env = os.environ.copy()
    env['METAL2VULKAN_SPIRV_VAL'] = str(args.validator.resolve(strict=True))
    env['METAL2VULKAN_REPRO_DIR'] = str(out / 'repros')
    descriptor = out / 'packing0.json'
    descriptor.write_text(json.dumps(PACKING0, indent=2))
    manifest = {'host_compile_only': True, 'device_runtime_verified': False,
                'quartzcore_uuid': '9e40b2eb-260c-3af1-ae45-a1a551a8c1b9',
                'source_evidence': {
                    'formats': 'QC MetalContext::MTLPixelFormat_codes @0x1d5b46d78: index80=BGRA,index10=L008,index115=RGhA (RGBA16Float)',
                    'packing0': 'QC @0x188381668 noL->packing0; table@0x188565090 header0x0130, attrs00f8/10e9/18ea/20db',
                    'native_ssbo': 'Mesa26.2.4 nir_lower_ssbo.c + gallium/drivers/panfrost/pan_nir_lower_sysvals.c + pan_cmdstream.c:panfrost_upload_ssbo_sysval'},
                'metallib_sha256': hashlib.sha256(args.metallib.read_bytes()).hexdigest(),
                'runtime_abi': {'ubo': 'bindingN -> hardwareUBO N+1; stageUBO0 reserved',
                    'ssbo': 'actual global GPU loads; UBO0 byte96+16*N {GPUVA:u64,size:u32,reserved:u32}',
                    'texture': 'binding order -> distinct hardware texture/sampler index',
                    'texture_sysvals': 'UBO0 byte352+32*N {levels,width,height,reserved,minLOD,maxLOD,bias,reserved}',
                    'viewport_scale': 'UBO0 byte512 float3', 'viewport_offset': 'UBO0 byte528 float3',
                    'raw_vertex_offset': 'UBO0 byte544 u32',
                    'base_vertex': 'UBO0 byte548 u32',
                    'base_instance': 'UBO0 byte552 u32'}, 'profiles': []}
    for family in args.family or FAMILIES:
        vertex, fragment, variants = FAMILIES[family]
        for variant, color, rows in variants:
            name = family + '_' + variant
            prefix = out / name
            record = {'family': family, 'variant': variant, 'rows': rows,
                      'vertex': vertex, 'fragment': fragment, 'color_format': color}
            command = [str(args.translator), str(args.metallib), str(prefix)+'.spv',
                       '--function', vertex, '--fragment', fragment, '--profile', str(args.profile),
                       '--color-format', '0:'+color, '--emit-meta', str(prefix)+'-meta.json', '--no-timeout']
            if family != 'home_affordance':
                command += ['--color-format', '1:'+('RG8Unorm' if variant=='r8' else color)]
            if family == 'buffer_image_blit':
                command += ['--color-format','2:R32Float']
            if family == 'home_affordance':
                command += ['--vertex-descriptor', str(descriptor)]
            if run(command, out/(name+'-air.log'), env=env):
                record['status']='air_translation_blocked';manifest['profiles'].append(record);continue
            meta = json.loads(Path(str(prefix)+'-meta.json').read_text())
            expected_outputs=1 if family=='home_affordance' else 3
            if meta['graphics']['color_outputs']!=expected_outputs:
                raise ValueError('actual AIR render outputs were dropped or changed')
            if meta['interface']['texture_writing_stages'] or meta['graphics']['fragment_writes_memory']:
                raise ValueError('per-target replay requires actual side-effect-free fragment AIR')
            record['resources'] = meta['interface']
            record['layout'] = meta['layout']
            record['graphics'] = meta['graphics']
            record['vertex_input'] = meta['vertex_input']
            record['specialization'] = [s['specialization'] for s in meta['stages']]
            record['spirv'] = {}
            for stage in ('vert', 'frag'):
                path = Path(str(prefix)+'.'+stage+'.spv')
                if run([str(args.validator),'--target-env','vulkan1.2',
                        '--uniform-buffer-standard-layout',str(path)],
                        out/(name+'-'+stage+'-validation.log')):
                    raise ValueError('actual stage validator rejected published module')
                data=path.read_bytes()
                record['spirv'][stage]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
            config=out/(name+'-profile.h')
            build_config(meta,prefix,config)
            for target in ([0] if family == 'home_affordance' else [0,1]):
                replay_name=name+'_rt'+str(target)
                replay=dict(record)
                replay['render_target']=target
                replay['output_color_format']='RG8Unorm' if variant=='r8' and target==1 else color
                replay['execution']='single_SFBD_target_replay' if family != 'home_affordance' else 'single_RT'
                replay['full_air_output_targets']=[0] if family == 'home_affordance' else [0,1]
                replay['native_output_packing']='RGBA16_RAW64_RG_BA' if color=='RGBA16Float' else 'native_unorm'
                manifest['profiles'].append(replay)
                binary=out/(replay_name+'-compile')
                if compile_backend(args.mesa_build,config,binary,out/(replay_name+'-build.log'),
                                   target,color=='RGBA16Float'):
                    replay['status']='backend_build_blocked';continue
                outputs=[out/(replay_name+'.'+stage+'.midgard') for stage in ('vert','frag')]
                rc=run([str(binary),str(prefix)+'.vert.spv',str(prefix)+'.frag.spv',
                        *map(str,outputs)],out/(replay_name+'-midgard.log'))
                replay['backend_status']=rc
                replay['midgard']={}
                text=(out/(replay_name+'-midgard.log')).read_text()
                for stage,path in zip(('vert','frag'),outputs):
                    if not path.is_file():continue
                    match=re.search(re.escape(str(path))+r': Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+) attributes=(\d+) ubos=(\d+) samplers=(\d+)',text)
                    if not match:raise ValueError('missing real renderer metadata')
                    replay['midgard'][stage]=dict(zip(('bytes','first_tag','textures','work_regs','tls','wls','attributes','ubos','samplers'),map(int,match.groups())))
                    replay['midgard'][stage]['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
                replay['status']='compiled' if rc==0 else 'backend_compile_blocked'
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'manifest':str(out/'manifest.json'),'profiles':[
        {k:v for k,v in p.items() if k in ('family','variant','status','backend_status','midgard')}
        for p in manifest['profiles']]},indent=2))

if __name__=='__main__':main()
