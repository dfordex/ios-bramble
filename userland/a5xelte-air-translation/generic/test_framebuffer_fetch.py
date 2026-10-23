#!/usr/bin/env python3
"""Authored input-attachment compiler regressions; no Apple input required."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import shutil

from dynamic_abi import build_manifest


def reflection():
    return {
        'layout': {'sets': [{'set': 0, 'flags': 0, 'bindings': [
            {'binding': 5, 'ty': 10, 'stages': 16, 'count': 1, 'flags': 0,
             'source': {'InputAttachment': 0}}]}], 'push_constants': []},
        'interface': {'slots': []},
        'graphics': {'rasterization_order_attachment_access': True,
                     'rasterization_samples': 1,
                     'input_attachments': [{'color_index': 0,
                        'input_attachment_index': 0, 'format_class': 'Float'}]},
        'stages': [{'stage': 'frag', 'entry_point': 'main', 'stage_flags': 0,
                    'required_subgroup_size': None,
                    'specialization': {'constants': []}}],
    }


ASM = '''OpCapability Shader
OpCapability InputAttachment
OpMemoryModel Logical GLSL450
OpEntryPoint Fragment %main "main" %out %attachment
OpExecutionMode %main OriginUpperLeft
OpDecorate %attachment DescriptorSet 0
OpDecorate %attachment Binding 5
OpDecorate %attachment InputAttachmentIndex ATTACHMENT
OpDecorate %out Location 0
%void = OpTypeVoid
%fn = OpTypeFunction %void
%float = OpTypeFloat 32
%v4 = OpTypeVector %float 4
%int = OpTypeInt 32 1
%v2i = OpTypeVector %int 2
%zero = OpConstant %int 0
%one = OpConstant %int 1
%coord = OpConstantComposite %v2i OFFSET %zero
%half = OpConstant %float 0.5
%image = OpTypeImage %float SubpassData 0 0 MULTISAMPLED 2 Unknown
%iptr = OpTypePointer UniformConstant %image
%attachment = OpVariable %iptr UniformConstant
%optr = OpTypePointer Output %v4
%out = OpVariable %optr Output
%main = OpFunction %void None %fn
%block = OpLabel
%img = OpLoad %image %attachment
%pixel = OpImageRead %v4 %img %coord
%value = OpVectorTimesScalar %v4 %pixel %half
OpStore %out %value
OpReturn
OpFunctionEnd
'''

def textured_reflection():
    meta = reflection()
    slot = {'stage': 'Fragment', 'class': 'Texture', 'index': 3}
    meta['layout']['sets'][0]['bindings'].append({
        'binding': 7, 'ty': 1, 'stages': 16, 'count': 1, 'flags': 0,
        'immutable_sampler': None,
        'source': {'CombinedTextureSampler': {'texture': slot,
            'sampler': {'sampler': {'Slot': 0}, 'compare': False,
                'integer': False, 'cube_gradient': False, 'raw': False}}}})
    meta['interface']['slots'] = [[slot, {'Texture': {
        'texture_type': 'Type2D', 'sampled_type': 'Float',
        'depth_compare': False, 'access': {'sample': True, 'read': False, 'write': False}}}]]
    return meta


TEXTURED_ASM = ASM.replace('%out %attachment\n', '%out %attachment %uv %sampled\n').replace(
    'OpDecorate %out Location 0',
    'OpDecorate %out Location 0\nOpDecorate %uv Location 0\n'
    'OpDecorate %sampled DescriptorSet 0\nOpDecorate %sampled Binding 7').replace(
    '%main = OpFunction',
    '%v2 = OpTypeVector %float 2\n%uvptr = OpTypePointer Input %v2\n'
    '%uv = OpVariable %uvptr Input\n%tex = OpTypeImage %float 2D 0 0 0 1 Unknown\n'
    '%combined = OpTypeSampledImage %tex\n%sptr = OpTypePointer UniformConstant %combined\n'
    '%sampled = OpVariable %sptr UniformConstant\n%quarter = OpConstant %float 0.25\n'
    '%zero_float = OpConstant %float 0\n%main = OpFunction').replace(
    '%value = OpVectorTimesScalar %v4 %pixel %half',
    '%previous = OpVectorTimesScalar %v4 %pixel %half\n%uvval = OpLoad %v2 %uv\n'
    '%texval = OpLoad %combined %sampled\n'
    '%sample = OpImageSampleImplicitLod %v4 %texval %uvval\n'
    '%scaled = OpVectorTimesScalar %v4 %sample %quarter\n'
    '%value = OpFAdd %v4 %previous %scaled')


def noise_reflection():
    meta = textured_reflection()
    slot = {'stage': 'Fragment', 'class': 'Texture', 'index': 9}
    immutable = {'mag_filter': 0, 'min_filter': 0, 'mipmap_mode': 0,
        'address_mode_u': 0, 'address_mode_v': 0, 'address_mode_w': 0,
        'mip_lod_bias': 0.0, 'max_anisotropy': None, 'compare': None,
        'min_lod': 0.0, 'max_lod': 0.25, 'border_color': 0,
        'reduction': 0, 'border_components': None}
    meta['layout']['sets'][0]['bindings'].append({
        'binding': 8, 'ty': 1, 'stages': 16, 'count': 1, 'flags': 0,
        'immutable_sampler': immutable,
        'source': {'CombinedTextureSampler': {'texture': slot,
            'sampler': {'sampler': {'Constexpr': [34901797601018002, 0]},
                'compare': False, 'integer': False,
                'cube_gradient': False, 'raw': False}}}})
    meta['interface']['slots'].append([slot, {'Texture': {
        'texture_type': 'Type2D', 'sampled_type': 'Float',
        'depth_compare': False, 'access': {'sample': True, 'read': False, 'write': False}}}])
    return meta


NOISE_ASM = TEXTURED_ASM.replace('%out %attachment %uv %sampled\n',
    '%out %attachment %uv %sampled %pos %noise\n').replace(
    'OpDecorate %out Location 0',
    'OpDecorate %pos BuiltIn FragCoord\nOpDecorate %noise DescriptorSet 0\n'
    'OpDecorate %noise Binding 8\nOpDecorate %out Location 0').replace(
    '%main = OpFunction',
    '%posptr = OpTypePointer Input %v4\n%pos = OpVariable %posptr Input\n'
    '%noise = OpVariable %sptr UniformConstant\n%eighth = OpConstant %float 0.125\n'
    '%main = OpFunction').replace(
    'OpStore %out %value',
    '%position = OpLoad %v4 %pos\n%xy = OpVectorShuffle %v2 %position %position 0 1\n'
    '%noise_uv = OpVectorTimesScalar %v2 %xy %eighth\n'
    '%noise_texture = OpLoad %combined %noise\n'
    '%noise_value = OpImageSampleImplicitLod %v4 %noise_texture %noise_uv\n'
    '%noise_scaled = OpVectorTimesScalar %v4 %noise_value %eighth\n'
    '%final = OpFAdd %v4 %value %noise_scaled\nOpStore %out %final')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--backend', type=Path)
    ap.add_argument('--spirv-as', default='spirv-as')
    ap.add_argument('--spirv-val', default='spirv-val')
    ap.add_argument('--fixture-out', type=Path)
    a = ap.parse_args()
    meta = reflection()
    manifest = build_manifest(meta, 'fragment')
    assert manifest == 'A5MIDGARD1\nstage fragment\npush_bytes 0\nframebuffer_fetch 5 0\n'
    # Ordered access, format and sample shape must all agree with native load.
    for field, value in [('rasterization_order_attachment_access', False),
                         ('rasterization_samples', 2),
                         ('input_attachments', [{'color_index': 1,
                            'input_attachment_index': 1, 'format_class': 'Float'}]),
                         ('input_attachments', [{'color_index': 0,
                            'input_attachment_index': 0, 'format_class': 'Uint'}])]:
        bad = copy.deepcopy(meta)
        bad['graphics'][field] = value
        try:
            build_manifest(bad, 'fragment')
        except ValueError:
            pass
        else:
            raise AssertionError(f'accepted unsupported {field}: {value}')
    if not a.backend:
        print('framebuffer fetch reflected ABI: positive and 4 negative cases PASS')
        return
    with tempfile.TemporaryDirectory(prefix='a5-fetch-compiler-', dir='/private/tmp') as tmp:
        folder = Path(tmp)
        def compile_case(name, *, offset='%zero', attachment=0, abi=manifest, success=True,
                         source_text=ASM, metadata=None):
            source = folder / f'{name}.spvasm'
            spv = source.with_suffix('.spv')
            code = source.with_suffix('.midgard')
            info = source.with_suffix('.json')
            text = source.with_suffix('.abi')
            source.write_text(source_text.replace('ATTACHMENT', str(attachment))
                .replace('MULTISAMPLED', '0').replace('OFFSET', offset))
            text.write_text(abi)
            subprocess.run([a.spirv_as, '--target-env', 'vulkan1.2', str(source), '-o', str(spv)], check=True)
            subprocess.run([a.spirv_val, '--target-env', 'vulkan1.2', str(spv)], check=True)
            result = subprocess.run([str(a.backend), '--dynamic-stage', 'fragment',
                str(spv), str(code), str(text), str(info)], stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True)
            if not success:
                assert result.returncode and not code.exists() and not info.exists(), result.stdout
                return
            assert result.returncode == 0, result.stdout
            j = json.loads(info.read_text())
            assert j['framebuffer_fetch'] is True and j['native_info']['bytes'] == code.stat().st_size
            assert j['native_info']['tls'] == j['native_info']['wls'] == 0
            assert j['outputs'] == [{'location': 4, 'base': 0, 'component': 0,
                                      'components': 4, 'bit_size': 32}]
            if a.fixture_out:
                destination = a.fixture_out / name
                destination.mkdir(parents=True, exist_ok=True)
                for path in (source, spv, code, info, text):
                    shutil.copy2(path, destination / ('shader' + path.suffix))
                if metadata:
                    (destination / 'reflection.json').write_text(json.dumps(metadata, indent=2)+'\n')
        compile_case('ordered-color0')
        textured = textured_reflection()
        compile_case('ordered-color0-texture', abi=build_manifest(textured, 'fragment'),
                     source_text=TEXTURED_ASM, metadata=textured)
        noise = noise_reflection()
        compile_case('ordered-color0-texture-noise', abi=build_manifest(noise, 'fragment'),
                     source_text=NOISE_ASM, metadata=noise)
        compile_case('nonzero-offset', offset='%one', success=False)
        compile_case('other-attachment', attachment=1, success=False)
        compile_case('undeclared-fetch', abi=manifest.replace('framebuffer_fetch 5 0\n', ''), success=False)
        compile_case('wrong-binding', abi=manifest.replace('framebuffer_fetch 5 0', 'framebuffer_fetch 6 0'), success=False)
        compile_case('duplicate-fetch', abi=manifest+'framebuffer_fetch 5 0\n', success=False)
        compile_case('other-color', abi=manifest.replace('framebuffer_fetch 5 0', 'framebuffer_fetch 5 1'), success=False)
    print('framebuffer fetch compiler: 3 actual authored tilebuffer stages + 6 native negatives PASS')


if __name__ == '__main__':
    main()
