#!/usr/bin/env python3
"""Reproduce the exact 0204 coord5/image17 QuartzCore specialization.

All translated modules, native code, and logs go to a private output directory.
The vertex specialization remains a candidate until the corresponding live
pipeline request is observed. This recipe does not infer texture pixel format.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
METALLIB_SHA = '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9'
VS = {'spirv_bytes': 5336,
      'spirv_sha256': 'b0a1ca6c74470282b84f1d513c8498ea7f04840aa5d0f3800cb63b4c4f20a8bf',
      'midgard_bytes': 2192,
      'midgard_sha256': 'e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96',
      'native_info': {'first_tag': 5, 'textures': 0, 'work_regs': 8,
                      'tls': 0, 'wls': 0, 'attributes': 3, 'ubos': 3, 'samplers': 0}}
VARIANTS = {
    606: {'capture_sha256': '62ebc426598d321a24bdb42b145a76a06449f491b971b2bf46ed38a32796f4bb',
          'frag': {'spirv_bytes': 808432,
                   'spirv_sha256': 'f4c90fda7ac7c32a6f98ef39430527302d6329644a6197ed87b4b2297902928a',
                   'midgard_bytes': 896,
                   'midgard_sha256': '5f1a9b4a037cb93f756bd3259f717d45c1a6622ee15d6504917c1582bf630e36',
                   'native_info': {'first_tag': 5, 'textures': 1, 'work_regs': 5,
                                   'tls': 0, 'wls': 0, 'attributes': 0, 'ubos': 5, 'samplers': 1}},
          'fragment_math': 'sample(Texture3, min(max(VAR0.xy, FragmentBuffer1.float4@112.xy), FragmentBuffer1.float4@112.zw), bias).a replicated to RGBA',
          'live_varyings': ['VAR0 float2 UV']},
}


def native_contract(old):
    contract = copy.deepcopy(old.NATIVE_CONTRACT)
    contract['fragment_live_buffers'].insert(0, {
        'metal_index': 1, 'binding': 2, 'native_ubo': 3, 'bytes': 128,
        'push_offset': 64, 'live_offset': 112, 'live_bytes': 16,
        'reflected_bytes': 168, 'purpose': 'float4 minimumXY/maximumXY UV clamp'})
    contract['fragment_texture']['uv_transform'] = \
        'min(max(VAR0.xy, FragmentBuffer1.float4@112.xy), FragmentBuffer1.float4@112.zw)'
    contract['fragment_declared_but_dead'] = ['SyntheticConstantBlob']
    contract['fragment_live_inputs'] = VARIANTS[606]['live_varyings']
    contract['fragment_math'] = VARIANTS[606]['fragment_math']
    contract['source_texture_format_captured'] = False
    return contract


def load_old():
    spec = importlib.util.spec_from_file_location('generic_0189', HERE / 'compile_0189.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_capture(path, profile):
    pin = VARIANTS[profile]
    if sha(path) != pin['capture_sha256']:
        raise ValueError('device capture identity differs')
    capture = json.loads(Path(path).read_text())
    if capture['function'] != 'fixed_frag_lph_cph' or len(capture['constants']) != 58 or \
            capture['indexed_constants'] != [] or \
            capture['constants']['fc_coord_function0'] != {
                'type': 49, 'bytes': 1, 'raw': '05'} or \
            capture['constants']['fc_image_function0'] != {
                'type': 49, 'bytes': 1, 'raw': '11'}:
        raise ValueError('captured typed specialization differs')
    args = []
    for name, value in sorted(capture['constants'].items()):
        kind = {49: 'uchar', 51: 'uchar3', 53: 'bool'}.get(value['type'])
        raw = bytes.fromhex(value['raw'])
        if not kind or len(raw) != value['bytes'] or \
                len(raw) != (3 if kind == 'uchar3' else 1):
            raise ValueError('unsupported typed specialization')
        vals = ','.join(('true' if x else 'false') if kind == 'bool' else str(x)
                        for x in raw)
        args.extend(('--constant', f'{name}:{kind}:{vals}'))
    return capture, args


def checked_meta(path, old):
    meta = json.loads(Path(path).read_text())
    # The resource and vertex descriptors are intentionally identical to the
    # observed 603 family. AIR branch selection is proved by stage hashes.
    # Compare stable ABI subtrees, not filename-bearing stage metadata.
    expected = {
        'layout': '81791a599050df321300b9d8c74391daa4114390ef7251f56e859a68e7db96cc',
        'interface': '4175c79fb077e3d46b110eb2723bda111129558357bc273bb6321e9824bd44e0',
        'vertex_input': '1e88563c6ec5b4c99c9aa3ca525fac433389593308a1fa817421ff46d30e07ff',
        'graphics': 'f16431ac899106b79ddb09296db4a2087aefd4cc6241981acea10e26356a92a9',
    }
    for key, digest in expected.items():
        blob = json.dumps(meta[key], sort_keys=True, separators=(',', ':')).encode()
        if hashlib.sha256(blob).hexdigest() != digest:
            raise ValueError(f'606 fragment family reflected {key} differs')
    if meta['graphics']['color_write_rules'] != [[0, 0x2222]]:
        raise ValueError('BGRA8 color rule differs')
    return meta


def checked_native_log(path, profile):
    text = Path(path).read_text()
    found = re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) '
                       r'work_regs=(\d+) tls=(\d+) wls=(\d+) attributes=(\d+) '
                       r'ubos=(\d+) samplers=(\d+)', text)
    if len(found) != 2:
        raise ValueError('missing native compiler stage records')
    keys = ('bytes', 'first_tag', 'textures', 'work_regs', 'tls', 'wls',
            'attributes', 'ubos', 'samplers')
    got = {stage: dict(zip(keys, map(int, found[i])))
           for i, stage in enumerate(('vert', 'frag'))}
    pins = {'vert': VS, 'frag': VARIANTS[profile]['frag']}
    for stage in pins:
        if got[stage] != {'bytes': pins[stage]['midgard_bytes'], **pins[stage]['native_info']}:
            raise ValueError(f'{stage} native metadata differs')
    final = text[text.rfind('MESA: info: shader: MESA_SHADER_FRAGMENT'):]
    for token in ('(float32)txb %12 (coord)', 'VARYING_SLOT_VAR0',
                  '@load_ubo (%6 (0x3), %7 (0x70))',
                  '@load_ubo (%9 (0x4), %1 (0x0))',
                  '@load_ubo (%1 (0x0), %0 (0x48))',
                  'fmax %5, %8.xy', 'fmin %11, %8.zw',
                  'fsat %20.wwww', 'texture0, fsampler0', 'FRAG_RESULT_DATA0'):
        if token not in final:
            raise ValueError(f'live 606 fragment path lost {token}')
    if '@load_interpolated_input' not in final or \
            'base=1, component=0, dest_type=float32, io location=VARYING_SLOT_VAR1' in final:
        raise ValueError('606 must consume only UV varying; color is declared dead')
    if re.search(r'@(?:load|store)_(?:global|ssbo|image)', final):
        raise ValueError('declared synthetic buffer became live')
    return got


def validate_receipt(path, capture_path, metallib_path):
    path = Path(path)
    j = json.loads(path.read_text())
    profile = j.get('profile_id')
    if profile not in VARIANTS or sha(metallib_path) != METALLIB_SHA:
        raise ValueError('unreviewed shader source/profile')
    old = load_old()
    capture, _ = checked_capture(capture_path, profile)
    meta = checked_meta(path.parent / 'reflection.json', old)
    native = checked_native_log(path.parent / 'midgard.log', profile)
    pins = {'vert': VS, 'frag': VARIANTS[profile]['frag']}
    contract = native_contract(old)
    if j.get('capture_sha256') != VARIANTS[profile]['capture_sha256'] or \
            j.get('metallib_sha256') != METALLIB_SHA or \
            j.get('compiled_function') != capture['function'] or \
            j.get('vertex_function') != 'fixed_vert_lph_spc' or \
            j.get('vertex_candidate') is not True or \
            j.get('pipeline_compatible') is not False or \
            j.get('host_only') is not True or \
            j.get('native_contract') != contract or \
            j.get('fragment_constants') != capture['constants'] or \
            j.get('vertex_candidate_constants') != [
                {'name': name, **capture['constants'][name]}
                for name in old.VERTEX_NAMES] or \
            j.get('configured_vertex_packing0') != old.PACKING0 or \
            j.get('reflected_layout') != meta['layout'] or \
            j.get('reflected_vertex_input') != meta['vertex_input'] or \
            j.get('sampler_variant_hashes') != {
                str(word): pins['frag']['midgard_sha256'] for word in (0, 2, 4, 6)}:
        raise ValueError('receipt identity or native contract differs')
    for stage in ('vert', 'frag'):
        rec = j['stages'][stage]
        if rec['native_info'] != native[stage]:
            raise ValueError('receipt native metadata differs')
        for kind, suffix in (('spirv', f'shader.{stage}.spv'),
                             ('midgard', f'{stage}.midgard')):
            f = path.parent / suffix
            if f.stat().st_size != pins[stage][f'{kind}_bytes'] or \
                    sha(f) != pins[stage][f'{kind}_sha256'] or \
                    rec[f'{kind}_bytes'] != f.stat().st_size or \
                    rec[f'{kind}_sha256'] != sha(f):
                raise ValueError(f'{stage} {kind} bytes changed')
    for word in (2, 4, 6):
        suffix = f'-normalized{word}'
        if f'kfrag_spec[]={{{{0,{word}}},{{3,168}},{{4,8}}}};' not in \
                (path.parent / f'profile{suffix}.h').read_text():
            raise ValueError('normalized sampler spec missing')
        checked_native_log(path.parent / f'midgard{suffix}.log', profile)
        for stage in ('vert', 'frag'):
            f = path.parent / f'{stage}{suffix}.midgard'
            if f.stat().st_size != pins[stage]['midgard_bytes'] or \
                    sha(f) != pins[stage]['midgard_sha256']:
                raise ValueError('normalized sampler changes native shader')
    return j


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile-id', type=int, choices=(606,), required=True)
    for key in ('capture', 'metallib', 'translator', 'validator', 'profile',
                'mesa-build', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    if out == HERE.parent or HERE.parent in out.parents:
        p.error('private compiler output cannot be inside source checkout')
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        p.error('private output must initially be empty')
    if sha(a.metallib) != METALLIB_SHA:
        p.error('stock QuartzCore library differs')
    old = load_old()
    capture, constants = checked_capture(a.capture, a.profile_id)
    (out / 'packing0.json').write_text(json.dumps(old.PACKING0, indent=2) + '\n')
    prefix = out / 'shader'
    command = [str(a.translator), str(a.metallib), str(prefix) + '.spv',
               '--profile', str(a.profile), '--function', 'fixed_vert_lph_spc',
               '--fragment', capture['function'], '--color-format',
               '0:BGRA8Unorm', '--vertex-descriptor', str(out / 'packing0.json'),
               '--emit-meta', str(out / 'reflection.json'), '--no-timeout',
               *constants]
    env = {**os.environ, 'METAL2VULKAN_SPIRV_VAL': str(a.validator),
           'MIDGARD_MESA_DEBUG': 'shaders'}
    with (out / 'translation.log').open('w') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    if 'spirv-val vulkan1.2: PASS' not in (out / 'translation.log').read_text():
        raise ValueError('SPIR-V validator did not run')
    meta = checked_meta(out / 'reflection.json', old)
    stages = {stage: out / f'shader.{stage}.spv' for stage in ('vert', 'frag')}
    for stage, path in stages.items():
        with (out / f'{stage}-validation.log').open('w') as log:
            subprocess.run([str(a.validator), '--target-env', 'vulkan1.2',
                            '--uniform-buffer-standard-layout', str(path)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    pins = {'vert': VS, 'frag': VARIANTS[a.profile_id]['frag']}
    for stage, path in stages.items():
        if path.stat().st_size != pins[stage]['spirv_bytes'] or \
                sha(path) != pins[stage]['spirv_sha256']:
            raise ValueError('translated exact stage fingerprint differs')
    backend = old.write_profile(out / 'profile.h', stages['vert'], stages['frag'], 0)
    compiled = backend.make_backend(out)
    if compiled.compile_backend(a.mesa_build, out / 'profile.h',
                                out / 'midgard-compiler', out / 'backend-build.log'):
        raise RuntimeError('host Midgard build failed')
    with (out / 'midgard.log').open('w') as log:
        subprocess.run([str(out / 'midgard-compiler'), str(stages['vert']),
                        str(stages['frag']), str(out / 'vert.midgard'),
                        str(out / 'frag.midgard')], env=env, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    native = checked_native_log(out / 'midgard.log', a.profile_id)
    for word in (2, 4, 6):
        suffix = f'-normalized{word}'
        profile = out / f'profile{suffix}.h'
        old.write_profile(profile, stages['vert'], stages['frag'], word)
        exe = out / f'midgard-compiler{suffix}'
        if compiled.compile_backend(a.mesa_build, profile, exe,
                                    out / f'backend-build{suffix}.log'):
            raise RuntimeError('sampler variant Midgard build failed')
        with (out / f'midgard{suffix}.log').open('w') as log:
            subprocess.run([str(exe), str(stages['vert']), str(stages['frag']),
                            str(out / f'vert{suffix}.midgard'),
                            str(out / f'frag{suffix}.midgard')], env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    contract = native_contract(old)
    vertex = [{'name': key, **capture['constants'][key]}
              for key in old.VERTEX_NAMES]
    receipt = {
        'schema': 1, 'profile_id': a.profile_id, 'host_only': True,
        'vertex_candidate': True, 'pipeline_compatible': False,
        'capture_sha256': VARIANTS[a.profile_id]['capture_sha256'],
        'metallib_sha256': METALLIB_SHA,
        'compiled_function': capture['function'],
        'vertex_function': 'fixed_vert_lph_spc',
        'fragment_constants': capture['constants'],
        'vertex_candidate_constants': vertex,
        'configured_vertex_packing0': old.PACKING0,
        'reflected_layout': meta['layout'],
        'reflected_vertex_input': meta['vertex_input'],
        'native_contract': contract,
        'sampler_variant_hashes': {str(word): pins['frag']['midgard_sha256']
                                   for word in (0, 2, 4, 6)},
        'stages': {stage: {'spirv_bytes': stages[stage].stat().st_size,
                           'spirv_sha256': sha(stages[stage]),
                           'midgard_bytes': (out / f'{stage}.midgard').stat().st_size,
                           'midgard_sha256': sha(out / f'{stage}.midgard'),
                           'native_info': native[stage]}
                   for stage in ('vert', 'frag')},
    }
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    validate_receipt(out / 'receipt.json', a.capture, a.metallib)
    print(json.dumps({'receipt': str(out / 'receipt.json'),
                      'profile_id': a.profile_id, 'pipeline_compatible': False}))


if __name__ == '__main__':
    main()
