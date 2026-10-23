#!/usr/bin/env python3
"""Turn translator-reflected stage ABI into the bounded dynamic backend input.

This contains no shader name, module fingerprint, or fixed-profile allowlist.
It accepts bounded readonly UBOs and sampled float2D texture/sampler pairs.
Actual native liveness is checked independently by misc_dynamic.h.
"""
import argparse
import json
from pathlib import Path


def build_manifest(meta, stage):
    if stage not in ('vertex', 'fragment'):
        raise ValueError('only vertex and fragment stages are supported')
    name, mask, short = ('Vertex', 1, 'vert') if stage == 'vertex' else ('Fragment', 16, 'frag')
    sets = meta['layout']['sets']
    if len(sets) != 1 or sets[0]['set'] != 0 or sets[0].get('flags', 0):
        raise ValueError('only descriptor set0 without flags is supported')
    slots = {(s['stage'], s['class'], s['index']): info for s, info in meta['interface']['slots']}
    def buffer_info(slot):
        if slot['stage'] != name or slot['class'] != 'Buffer':
            raise ValueError('buffer stage or class differs')
        info = slots[(slot['stage'], slot['class'], slot['index'])]['Buffer']
        if info['access'] != {'read': True, 'write': False} or info['form'] != {'Descriptor': 'UniformWords'}:
            raise ValueError('only readonly UniformWords buffers are supported')
        window = info['window']['Bounded']
        if window['start'] or not 0 < window['len'] <= 4096:
            raise ValueError('unsupported buffer window')
        return window['len']
    pushes = [p for p in meta['layout']['push_constants'] if p['stages'] & mask]
    push = max((p['offset'] + p['size'] for p in pushes), default=0)
    if push > 80 or push % 4 or any(p['offset'] < 0 or p['size'] < 0 for p in pushes):
        raise ValueError('unsupported push constant range')
    lines = ['A5MIDGARD1', 'stage ' + stage, f'push_bytes {push}']
    textures, fetches = 0, 0
    for binding in sets[0]['bindings']:
        if not binding['stages'] & mask:
            continue
        if binding['count'] != 1 or binding['flags']:
            raise ValueError('descriptor arrays and flags are unsupported')
        number, kind = binding['binding'], binding['ty']
        if kind == 6:
            length = buffer_info(binding['source']['Buffer'])
            if not 0 <= number < 7:
                raise ValueError('native UBO table overflow')
            lines.append(f'binding {number} uniform {length}')
        elif kind == 7 and binding['source'] == {'Synthetic': {'stage': name, 'binding': 'ConstantBlob'}}:
            # ConstantBlob is only admitted if optimized away. A live storage
            # or global load is rejected by native liveness analysis.
            lines.append(f'binding {number} storage 0')
        elif kind == 1:
            source = binding['source']['CombinedTextureSampler']
            texture = source['texture']
            info = slots[(texture['stage'], texture['class'], texture['index'])]['Texture']
            sampler = source['sampler']
            selection = sampler['sampler']
            if 'Constexpr' in selection:
                if binding.get('immutable_sampler') != {
                    'mag_filter': 0, 'min_filter': 0, 'mipmap_mode': 0,
                    'address_mode_u': 0, 'address_mode_v': 0, 'address_mode_w': 0,
                    'mip_lod_bias': 0.0, 'max_anisotropy': None, 'compare': None,
                    'min_lod': 0.0, 'max_lod': 0.25, 'border_color': 0,
                    'reduction': 0, 'border_components': None}:
                    raise ValueError('unsupported immutable sampler state')
            elif set(selection) != {'Slot'} or binding.get('immutable_sampler') is not None:
                raise ValueError('unsupported sampler source')
            if texture['stage'] != name or info['texture_type'] != 'Type2D' or info['sampled_type'] != 'Float' or \
                    info['depth_compare'] or info['access'] != {'sample': True, 'read': False, 'write': False} or \
                    sampler['compare'] or sampler['integer'] or sampler['cube_gradient'] or sampler['raw'] or textures >= 4:
                raise ValueError('unsupported sampled texture ABI')
            lines.append(f'texture {number} {textures}')
            textures += 1
        elif kind == 10 and binding['source'] == {'InputAttachment': 0} and stage == 'fragment':
            graphics = meta['graphics']
            if fetches or not graphics['rasterization_order_attachment_access'] or \
                    graphics['rasterization_samples'] != 1 or \
                    graphics['input_attachments'] != [{'color_index': 0, 'input_attachment_index': 0,
                                                       'format_class': 'Float'}]:
                raise ValueError('unsupported unordered or multisampled framebuffer fetch')
            lines.append(f'framebuffer_fetch {number} 0')
            fetches += 1
        else:
            raise ValueError('unsupported descriptor resource')
    stages = [s for s in meta['stages'] if s['stage'] == short]
    if len(stages) != 1 or stages[0]['entry_point'] != 'main' or stages[0]['stage_flags'] or \
            stages[0]['required_subgroup_size'] is not None:
        raise ValueError('unsupported stage execution model')
    for spec in stages[0]['specialization']['constants']:
        key = spec['key']
        if spec['size'] != 4:
            raise ValueError('only 32-bit backend specialization is supported')
        if set(key) == {'RangeAtBindOffset'}:
            value = buffer_info(key['RangeAtBindOffset'])
        elif set(key) == {'SamplerState'}:
            sampler = key['SamplerState']
            slot = sampler['slot']
            if slot['stage'] != name or slot['class'] != 'Sampler' or sampler['fields'] != 2147483655 or \
                    spec['unread_bits'] != 4294967288:
                raise ValueError('unsupported sampler specialization fields')
            value = 0  # normalized coordinates; runtime enforces clamp/filters
        else:
            raise ValueError('unsupported backend specialization key')
        lines.append(f"spec {spec['id']} {value}")
    if len(lines) > 64:
        raise ValueError('ABI manifest exceeds parser bound')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('reflection', type=Path)
    p.add_argument('stage', choices=('vertex', 'fragment'))
    p.add_argument('output', type=Path)
    a = p.parse_args()
    a.output.write_text(build_manifest(json.loads(a.reflection.read_text()), a.stage))
