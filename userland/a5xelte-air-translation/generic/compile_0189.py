#!/usr/bin/env python3
"""Compile the exact captured 0189 textured QuartzCore fragment privately.

The 58 fragment constants came from the phone. The four vertex constants in
this recipe are a UV-capable host candidate, not a captured live pipeline.
Stock metallib, SPIR-V, Midgard code and all logs remain outside Git.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CAPTURE_SHA = '3f934fe03acddd94995188de565c67c4a89a60acc3d2d66dc6f80e2584404025'
METALLIB_SHA = '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9'
REFLECTION_SHA = 'c30d627acd04ba2d5f7b23aecc87a669736b708e80557f0029a0a9e8ba9683aa'
PIN = {
    'vert': {'spirv_bytes': 5336,
             'spirv_sha256': 'b0a1ca6c74470282b84f1d513c8498ea7f04840aa5d0f3800cb63b4c4f20a8bf',
             'midgard_bytes': 2192,
             'midgard_sha256': 'e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96',
             'native_info': {'first_tag': 5, 'textures': 0, 'work_regs': 8,
                             'tls': 0, 'wls': 0, 'attributes': 3, 'ubos': 3, 'samplers': 0}},
    'frag': {'spirv_bytes': 808432,
             'spirv_sha256': 'f5e9e9b98a6758205f6235cc972a5338b41c60ded9197b5e517724607ed16341',
             'midgard_bytes': 880,
             'midgard_sha256': 'e4cf4d31a87bde096cc7cc57a12818f79296e3998d22d9c6c5139a9887f30047',
             'native_info': {'first_tag': 5, 'textures': 1, 'work_regs': 5,
                             'tls': 0, 'wls': 0, 'attributes': 0, 'ubos': 5, 'samplers': 1}},
}
PACKING0 = {
    'layouts': {'1': {'stride': 48, 'step_function': 'PerVertex', 'step_rate': 1}},
    'attributes': {str(i): {'format': fmt, 'offset': offset, 'buffer_index': 1}
                   for i, (fmt, offset) in enumerate((('Float4', 0), ('Float2', 16),
                                                      ('Float2', 24), ('Half4', 32)))},
}
NONZERO = {'fc_attachment_count': 1, 'fc_blend_function': 54,
           'fc_framebuffer_fetch': 1, 'fc_has_image_0A': 1,
           'fc_has_lod_bias': 1, 'fc_image_count': 1,
           'fc_plane_count0': 1, 'fc_texcoord_count0': 1,
           'fc_texture_function': 1}
VERTEX_NAMES = ('fc_generic', 'fc_texcoord_count0', 'fc_texcoord_count1',
                'fc_vertex_layout')
NATIVE_CONTRACT = {
    'vertex_live_buffers': [
        {'metal_index': 2, 'binding': 0, 'native_ubo': 1, 'bytes': 64,
         'push_offset': 0},
        {'metal_index': 3, 'binding': 1, 'native_ubo': 2, 'bytes': 16,
         'push_offset': 4}],
    'fragment_live_buffers': [
        {'metal_index': 2, 'binding': 3, 'native_ubo': 4, 'bytes': 8,
         'push_offset': 68, 'live_offset': 0, 'purpose': 'LOD bias'}],
    'fragment_texture': {'metal_index': 3, 'binding': 5,
                         'native_texture': 0, 'type': '2D float sample',
                         'uv_transform': 'normalized UV passed directly to sampler'},
    'fragment_sampler': {'metal_index': 0, 'binding': 5,
                         'native_sampler': 0, 'source': 'runtime Slot0'},
    'push_color_write_rule': {'offset': 72, 'bytes': 4, 'value': 0x2222},
    'vertex_attributes': ['Float4@0', 'Float2@16 UV', 'Half4@32 color'],
    'vertex_outputs': ['POS float4', 'PSIZ float1', 'VAR0 UV vec2',
                       'VAR1 color vec4'],
    'fragment_live_inputs': ['VAR0 UV vec2'],
    'fragment_output': 'RT0 float4',
    'fragment_declared_but_dead': ['Metal Fragment Buffer1 168 bytes',
                                   'SyntheticConstantBlob'],
    'sampler_state_live_capture': False,
    'sampler_state_spec_id': 0,
    'sampler_state_read_mask': 7,
    'sampler_state_word': 0,
    'equivalent_normalized_sampler_words': [0, 2, 4, 6],
    'sampler_required_state': 'normalized coordinates; nearest/linear min and mag; ClampToEdge S/T/R at runtime',
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def stock_capture(path):
    if sha(path) != CAPTURE_SHA:
        raise ValueError('not the complete 0189 device capture')
    capture = json.loads(Path(path).read_text())
    values = capture['constants']
    if capture['function'] != 'fixed_frag_lph_cph' or len(values) != 58 or \
            capture['indexed_constants'] != []:
        raise ValueError('0189 function or constant count differs')
    result = []
    for name, item in sorted(values.items()):
        kind = {49: 'uchar', 51: 'uchar3', 53: 'bool'}.get(item['type'])
        width = 3 if kind == 'uchar3' else 1
        if not kind or item['bytes'] != width or len(item['raw']) != 2 * width:
            raise ValueError(f'0189 constant type/width differs: {name}')
        raw = bytes.fromhex(item['raw'])
        if name in NONZERO:
            if kind == 'uchar3' or raw != bytes([NONZERO[name]]):
                raise ValueError(f'0189 nonzero constant differs: {name}')
        elif any(raw):
            raise ValueError(f'0189 extra nonzero constant: {name}')
        arg = ','.join(('true' if x else 'false') if kind == 'bool'
                       else str(x) for x in raw)
        result.extend(('--constant', f'{name}:{kind}:{arg}'))
    if not set(NONZERO).issubset(values) or not set(VERTEX_NAMES).issubset(values):
        raise ValueError('0189 required constant absent')
    return capture, result


def reflection(meta):
    def stable(item):
        if isinstance(item, dict):
            return {key: (value.rsplit('/', 1)[-1] if key == 'spirv' and
                          isinstance(value, str) else stable(value))
                    for key, value in item.items()}
        if isinstance(item, list):
            return [stable(value) for value in item]
        return item
    if hashlib.sha256(canonical(stable(meta))).hexdigest() != REFLECTION_SHA:
        raise ValueError('0189 reflected shader ABI changed')
    slots = {(k['stage'], k['class'], k['index']): v
             for k, v in meta['interface']['slots']}
    for key, length in ((('Vertex', 'Buffer', 2), 64),
                        (('Vertex', 'Buffer', 3), 16),
                        (('Fragment', 'Buffer', 1), 168),
                        (('Fragment', 'Buffer', 2), 8)):
        if slots[key]['Buffer']['window']['Bounded'] != {'start': 0, 'len': length}:
            raise ValueError(f'0189 buffer window differs: {key}')
    if slots[('Fragment', 'Texture', 3)]['Texture']['texture_type'] != 'Type2D' or \
            not slots[('Fragment', 'Texture', 3)]['Texture']['access']['sample'] or \
            slots[('Fragment', 'Sampler', 0)]['Sampler']['compare'] or \
            meta['layout']['sets'][0]['bindings'][5]['source']['CombinedTextureSampler'] != {
                'texture': {'stage': 'Fragment', 'class': 'Texture', 'index': 3},
                'sampler': {'sampler': {'Slot': 0}, 'compare': False,
                            'integer': False, 'cube_gradient': False, 'raw': False}} or \
            meta['graphics']['color_write_rules'] != [[0, 0x2222]]:
        raise ValueError('0189 texture/sampler/output contract differs')
    return meta


def native_log(log):
    text = Path(log).read_text()
    infos = re.findall(
        r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) '
        r'tls=(\d+) wls=(\d+) attributes=(\d+) ubos=(\d+) samplers=(\d+)', text)
    if len(infos) != 2:
        raise ValueError('missing or ambiguous native compilation info')
    keys = ('bytes', 'first_tag', 'textures', 'work_regs', 'tls', 'wls',
            'attributes', 'ubos', 'samplers')
    result = {stage: dict(zip(keys, map(int, infos[i])))
              for i, stage in enumerate(('vert', 'frag'))}
    for stage in ('vert', 'frag'):
        expected = {'bytes': PIN[stage]['midgard_bytes'],
                    **PIN[stage]['native_info']}
        if result[stage] != expected:
            raise ValueError(f'0189 {stage} native info differs')
    vi = text.rfind('MESA: info: shader: MESA_SHADER_VERTEX')
    fi = text.rfind('MESA: info: shader: MESA_SHADER_FRAGMENT')
    if vi < 0 or fi <= vi:
        raise ValueError('missing final Mesa NIR')
    vertex, fragment = text[vi:fi], text[fi:]
    for token in ('VERT_ATTRIB_GENERIC0', 'VERT_ATTRIB_GENERIC1',
                  'VERT_ATTRIB_GENERIC2', 'VARYING_SLOT_VAR0',
                  'VARYING_SLOT_VAR1', 'VARYING_SLOT_POS',
                  '@load_ubo (%68 (0x2), %0 (0x0))'):
        if token not in vertex:
            raise ValueError(f'0189 vertex interface lost: {token}')
    for token in ('(float32)txb', 'VARYING_SLOT_VAR0', 'FRAG_RESULT_DATA0',
                  '@load_ubo (%6 (0x4), %1 (0x0))',
                  '@load_ubo (%1 (0x0), %0 (0x48))',
                  'TEX.2d.kill AL0.f32, texture0, fsampler0'):
        if token not in fragment:
            raise ValueError(f'0189 fragment interface lost: {token}')
    if re.search(r'@(?:load|store)_(?:global|ssbo|image)', fragment):
        raise ValueError('0189 synthetic blob/storage unexpectedly live')
    if '0x164' in fragment or 'FFLOOR' in fragment or \
            '(float32)txb %5 (coord)' not in fragment:
        raise ValueError('0189 normalized sampler UV path changed')
    return result


def write_profile(path, vertex, fragment, sampler_word=0):
    if sampler_word not in (0, 2, 4, 6):
        raise ValueError('only normalized nearest/linear sampler words are supported')
    spec = importlib.util.spec_from_file_location('old_generic',
                                                  ROOT / 'generic' / 'compile_0185.py')
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    path.write_text('''/* Private, exact 0189 host shader profile. */
static const struct a5_resource_binding kvert_bindings[]={{0,nir_descriptor_type_uniform_buffer},{1,nir_descriptor_type_uniform_buffer}};
static const struct a5_resource_binding kfrag_bindings[]={{2,nir_descriptor_type_uniform_buffer},{3,nir_descriptor_type_uniform_buffer},{4,nir_descriptor_type_storage_buffer}};
static const struct a5_spec_value kvert_spec[]={{1,64},{2,16}};
static const struct a5_spec_value kfrag_spec[]={{0,%d},{3,168},{4,8}};
static const struct a5_texture_binding kvert_textures[]={{0,0}};
static const struct a5_texture_binding kfrag_textures[]={{5,0}};
static const struct a5_stage_profile kStages[]={
 {UINT64_C(0x%016x),kvert_bindings,2,kvert_spec,2,kvert_textures,0,8},
 {UINT64_C(0x%016x),kfrag_bindings,3,kfrag_spec,3,kfrag_textures,1,76}
};
''' % (sampler_word, old.fnv(vertex.read_bytes()), old.fnv(fragment.read_bytes())))
    return old


def validate_receipt(receipt_path, capture_path, metallib_path,
                     vertex_capture_path=None):
    """Reject substitutions; a vertex capture may only confirm, never alter, this recipe."""
    receipt_path = Path(receipt_path)
    receipt = json.loads(receipt_path.read_text())
    capture, _ = stock_capture(capture_path)
    if sha(metallib_path) != METALLIB_SHA or \
            receipt.get('profile_id') != 603 or \
            receipt.get('capture_sha256') != CAPTURE_SHA or \
            receipt.get('metallib_sha256') != METALLIB_SHA or \
            receipt.get('compiled_function') != capture['function'] or \
            receipt.get('vertex_function') != 'fixed_vert_lph_spc' or \
            receipt.get('vertex_candidate') is not True or \
            receipt.get('device_pair_verified') is not False or \
            receipt.get('pipeline_compatible') is not False or \
            receipt.get('configured_vertex_packing0') != PACKING0 or \
            receipt.get('host_only') is not True or \
            receipt.get('native_contract') != NATIVE_CONTRACT or \
            receipt.get('fragment_constants') != capture['constants']:
        raise ValueError('0189 receipt identity or proof boundary differs')
    if vertex_capture_path is not None:
        raise ValueError('0189 live vertex capture not yet available')
    meta = reflection(json.loads((receipt_path.parent / 'reflection.json').read_text()))
    if receipt['reflected_layout'] != meta['layout'] or \
            receipt['reflected_vertex_input'] != meta['vertex_input']:
        raise ValueError('0189 reflected ABI differs from receipt')
    native_log(receipt_path.parent / 'midgard.log')
    normalized_words = (0, 2, 4, 6)
    if receipt.get('sampler_variant_hashes') != {
            str(word): PIN['frag']['midgard_sha256'] for word in normalized_words}:
        raise ValueError('0189 normalized nearest/linear variants not proven equivalent')
    for word in normalized_words:
        suffix = '' if word == 0 else f'-normalized{word}'
        profile = receipt_path.parent / f'profile{suffix}.h'
        if f'kfrag_spec[]={{{{0,{word}}},{{3,168}},{{4,8}}}};' not in profile.read_text():
            raise ValueError(f'0189 sampler specialization word {word} differs')
        if word:
            native_log(receipt_path.parent / f'midgard{suffix}.log')
            for stage in ('vert', 'frag'):
                variant = receipt_path.parent / f'{stage}{suffix}.midgard'
                if variant.stat().st_size != PIN[stage]['midgard_bytes'] or \
                        sha(variant) != PIN[stage]['midgard_sha256']:
                    raise ValueError(f'0189 sampler word {word} changes native {stage}')
    candidate_constants = [
        {'name': name, 'type': capture['constants'][name]['type'],
         'bytes': capture['constants'][name]['bytes'],
         'raw': capture['constants'][name]['raw']} for name in VERTEX_NAMES]
    if receipt.get('vertex_candidate_constants') != candidate_constants:
        raise ValueError('0189 candidate vertex constants differ')
    for stage in ('vert', 'frag'):
        item = receipt['stages'][stage]
        if item['native_info'] != {
                'bytes': PIN[stage]['midgard_bytes'], **PIN[stage]['native_info']}:
            raise ValueError(f'0189 {stage} native metadata differs')
        for kind, name in (('spirv', f'fixed_textured.{stage}.spv'),
                           ('midgard', f'{stage}.midgard')):
            path = receipt_path.parent / name
            if path.stat().st_size != PIN[stage][f'{kind}_bytes'] or \
                    sha(path) != PIN[stage][f'{kind}_sha256'] or \
                    item[f'{kind}_bytes'] != path.stat().st_size or \
                    item[f'{kind}_sha256'] != sha(path):
                raise ValueError(f'0189 {stage} {kind} differs')
    return receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('capture', 'metallib', 'translator', 'validator', 'profile',
                 'mesa-build', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    if out == ROOT or ROOT in out.parents:
        p.error('generated artifacts must stay outside the checkout')
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        p.error('output must be empty')
    capture, constants = stock_capture(a.capture)
    if sha(a.metallib) != METALLIB_SHA:
        p.error('stock QuartzCore metallib differs')
    (out / 'packing0.json').write_text(json.dumps(PACKING0, indent=2) + '\n')
    prefix = out / 'fixed_textured'
    command = [str(a.translator), str(a.metallib), str(prefix) + '.spv',
               '--profile', str(a.profile), '--function', 'fixed_vert_lph_spc',
               '--fragment', capture['function'], '--color-format',
               '0:BGRA8Unorm', '--vertex-descriptor', str(out / 'packing0.json'),
               '--emit-meta', str(out / 'reflection.json'), '--no-timeout',
               *constants]
    env = {**os.environ, 'METAL2VULKAN_SPIRV_VAL': str(a.validator)}
    with (out / 'translation.log').open('w') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    if 'spirv-val vulkan1.2: PASS' not in (out / 'translation.log').read_text():
        raise ValueError('SPIR-V validation did not run')
    meta = reflection(json.loads((out / 'reflection.json').read_text()))
    stages = {s: out / f'fixed_textured.{s}.spv' for s in ('vert', 'frag')}
    for stage, path in stages.items():
        with (out / f'{stage}-validation.log').open('w') as log:
            subprocess.run([str(a.validator), '--target-env', 'vulkan1.2',
                            '--uniform-buffer-standard-layout', str(path)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    old = write_profile(out / 'profile.h', stages['vert'], stages['frag'])
    backend = old.make_backend(out)
    if backend.compile_backend(a.mesa_build, out / 'profile.h',
                               out / 'midgard-compiler',
                               out / 'backend-build.log'):
        raise RuntimeError('Mesa Midgard host build failed')
    env['MIDGARD_MESA_DEBUG'] = 'shaders'
    with (out / 'midgard.log').open('w') as log:
        subprocess.run([str(out / 'midgard-compiler'), str(stages['vert']),
                        str(stages['frag']), str(out / 'vert.midgard'),
                        str(out / 'frag.midgard')], env=env, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    info = native_log(out / 'midgard.log')
    # The reflected SamplerState field mask is 0x80000007. Bit 0 means
    # pixel coordinates, not address mode S; bit 1/2 select min/mag linear.
    # The Metal provider accepts normalized coordinates with nearest/linear
    # min/mag, so verify that every admitted word has identical native code.
    for word in (2, 4, 6):
        suffix = f'-normalized{word}'
        profile = out / f'profile{suffix}.h'
        write_profile(profile, stages['vert'], stages['frag'], word)
        compiler = out / f'midgard-compiler{suffix}'
        if backend.compile_backend(a.mesa_build, profile, compiler,
                                   out / f'backend-build{suffix}.log'):
            raise RuntimeError(f'Mesa Midgard sampler word {word} build failed')
        with (out / f'midgard{suffix}.log').open('w') as log:
            subprocess.run([str(compiler), str(stages['vert']),
                            str(stages['frag']), str(out / f'vert{suffix}.midgard'),
                            str(out / f'frag{suffix}.midgard')], env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        native_log(out / f'midgard{suffix}.log')
        for stage in ('vert', 'frag'):
            variant = out / f'{stage}{suffix}.midgard'
            if variant.stat().st_size != PIN[stage]['midgard_bytes'] or \
                    sha(variant) != PIN[stage]['midgard_sha256']:
                raise ValueError(f'normalized sampler word {word} changes {stage} native code')
    vertex_constants = [{'name': name, 'type': capture['constants'][name]['type'],
                         'bytes': capture['constants'][name]['bytes'],
                         'raw': capture['constants'][name]['raw']}
                        for name in VERTEX_NAMES]
    receipt = {
        'schema': 1, 'profile_id': 603, 'host_only': True,
        'vertex_candidate': True, 'device_pair_verified': False,
        'pipeline_compatible': False,
        'capture_sha256': CAPTURE_SHA, 'metallib_sha256': METALLIB_SHA,
        'compiled_function': capture['function'],
        'vertex_function': 'fixed_vert_lph_spc',
        'fragment_constants': capture['constants'],
        'vertex_candidate_constants': vertex_constants,
        'configured_vertex_packing0': PACKING0,
        'reflected_layout': meta['layout'],
        'reflected_vertex_input': meta['vertex_input'],
        'native_contract': NATIVE_CONTRACT,
        'sampler_variant_hashes': {str(word): PIN['frag']['midgard_sha256']
                                   for word in (0, 2, 4, 6)},
        'stages': {stage: {'spirv_bytes': stages[stage].stat().st_size,
                           'spirv_sha256': sha(stages[stage]),
                           'midgard_bytes': (out / f'{stage}.midgard').stat().st_size,
                           'midgard_sha256': sha(out / f'{stage}.midgard'),
                           'native_info': info[stage]}
                   for stage in stages},
    }
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    validate_receipt(out / 'receipt.json', a.capture, a.metallib)
    print(json.dumps({'receipt': str(out / 'receipt.json'),
                      'profile_id': 603, 'vertex_candidate': True,
                      'pipeline_compatible': False}))


if __name__ == '__main__':
    main()
