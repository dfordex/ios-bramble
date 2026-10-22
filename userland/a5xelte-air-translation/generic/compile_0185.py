#!/usr/bin/env python3
"""Compile the exact captured QuartzCore 0185/0186 fragments privately.

The metallib, captured constants, SPIR-V and native Midgard bytes are inputs or
outputs outside the checkout. The vertex stage is only a host candidate until
the actual pipeline's vertex function and render state are captured on device.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PINNED_METALLIB_SHA256 = '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9'
PINNED_VERTEX = {
    'spirv': '0528d04cf9a3ff58fb8fb239c8d0cc3a68d8f92655933ee2ae3e0eef9f4d9ea0',
    'midgard': '3cdf2b0db0b9992ce887242e7cac282cd70c3f8051e3ace3e791a0b676193a79',
}
PINNED_REAL_VERTEX_SPIRV = 'c022ec8724edf2fba6c7860686d07bf3c47c22577804f868f61ebf145018ecbc'
PINNED_REAL_VERTEX_CAPTURE = '4a22ff76f6f39a50069498ca7a81e2a34a15b693f610ab70ec15f2d82164eb13'
PINNED_FRAGMENT_NATIVE = 'e66041333f6452510cda4d0ee1f1c1edf443a12007a989871a1546791deb0834'
PROFILES = {
    'fixed_frag_lpf_cpf': {
        'profile_id': 600,
        'compiled': 'fixed_frag_lph_cpf',
        'capture_sha256': 'e2f809f528beff1876b1bdfbb4305fd750fd70fc587d804bb7bc071417bc21f1',
        'fragment_spirv_sha256': '99c1da83118acbc443b29f4a6db75e6f9abaaaabe6bee568a2711c929f6d1f6e',
        'reason': '0185 unavailable LPF; offline stock LPH CPF probe, not observed at runtime',
    },
    'fixed_frag_lph_cph': {
        'profile_id': 601,
        'compiled': 'fixed_frag_lph_cph',
        'capture_sha256': '3b2325f832c093b38b2ea1fdfe153509669c99b3bc3134cbe5d14255e5a17bf8',
        'fragment_spirv_sha256': 'f271a311587f085c95eae36250cba6466308135691fcf04d8adbabd167d55ac1',
        'reason': '0186 real stock LPH CPH function requested by QuartzCore',
    },
}
PROFILE_602 = dict(PROFILES['fixed_frag_lph_cph'],
    profile_id=602, vertex='fixed_vert_lph_spc',
    vertex_spirv_sha256=PINNED_REAL_VERTEX_SPIRV,
    reason='0187 actual stock vertex paired with 0186 actual stock fragment')


def profile_for_capture(fragment_path, vertex_path=None):
    fragment = json.loads(Path(fragment_path).read_text())
    captured_constants(Path(fragment_path))
    profile = PROFILES[fragment['function']]
    if vertex_path is None:
        return dict(profile, vertex='std_vert0_lph',
                    vertex_spirv_sha256=PINNED_VERTEX['spirv'])
    if fragment['function'] != 'fixed_frag_lph_cph':
        raise ValueError('real vertex 0187 can only pair with actual CPH fragment 0186')
    vertex = json.loads(Path(vertex_path).read_text())
    if sha(Path(vertex_path)) != PINNED_REAL_VERTEX_CAPTURE or \
            vertex.get('function') != 'fixed_vert_lph_spc' or \
            vertex.get('indexed_count') != 0 or vertex.get('truncated'):
        raise ValueError('0187 vertex capture identity differs')
    expected = {'fc_generic': 53, 'fc_texcoord_count0': 49,
                'fc_texcoord_count1': 49, 'fc_vertex_layout': 49}
    if set(vertex['constants']) != set(expected):
        raise ValueError('0187 vertex constant names differ')
    for name, ty in expected.items():
        item = vertex['constants'][name]
        if item['type'] != ty or item['values'] != [0] or item['raw'] != '00':
            raise ValueError(f'0187 vertex constant differs: {name}')
    fragment_constants = fragment['constants']
    if any(vertex['constants'][name]['values'] !=
           fragment_constants[name]['values'] for name in expected):
        raise ValueError('fragment and vertex constants conflict')
    return PROFILE_602
CONSTANT_CONTRACT_SHA256 = 'ce2da02786df035dba926c6959c2c03aeddf4737577538bd168e1b7921f6341b'
PACKING0 = {
    'layouts': {'1': {'stride': 48, 'step_function': 'PerVertex', 'step_rate': 1}},
    'attributes': {str(i): {'format': f, 'offset': o, 'buffer_index': 1}
                   for i, (f, o) in enumerate((('Float4', 0), ('Float2', 16),
                                               ('Float2', 24), ('Half4', 32)))},
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fnv(data):
    value = 0xcbf29ce484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    return value


def run(command, log, env=None):
    proc = subprocess.run(command, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, env=env,
                          timeout=600, check=False)
    log.write_text(proc.stdout)
    if proc.returncode:
        raise RuntimeError(f'{command[0]} exited {proc.returncode}: {log}')


def captured_constants(path):
    capture = json.loads(path.read_text())
    if capture['function'] not in PROFILES or \
            sha(path) != PROFILES[capture['function']]['capture_sha256']:
        raise ValueError('capture must exactly match documented 0185 or 0186')
    constants = capture['constants']
    contract = json.dumps({key: {'type': item['type'], 'raw': item['raw']}
                           for key, item in sorted(constants.items())},
                          separators=(',', ':'))
    if hashlib.sha256(contract.encode()).hexdigest() != CONSTANT_CONTRACT_SHA256:
        raise ValueError('named/type/raw specialization contract differs')
    if len(constants) != 58:
        raise ValueError('expected all 58 captured function constants')
    expected = {'fc_attachment_count': 1, 'fc_blend_function': 54,
                'fc_framebuffer_fetch': 1}
    result = []
    for name, item in sorted(constants.items()):
        kind = {49: 'uchar', 51: 'uchar3', 53: 'bool'}.get(item['type'])
        if kind is None:
            raise ValueError(f'unsupported captured constant type: {name}')
        values = item['values']
        if len(values) != (3 if kind == 'uchar3' else 1):
            raise ValueError(f'wrong constant width: {name}')
        if any(v != 0 for v in values) and (name not in expected or
                                           values != [expected[name]]):
            raise ValueError(f'unexpected nonzero 0185 constant: {name}')
        if name in expected and values != [expected[name]]:
            raise ValueError(f'missing captured nonzero constant: {name}')
        payload = ','.join(('true' if v else 'false') if kind == 'bool'
                           else str(v) for v in values)
        result += ['--constant', f'{name}:{kind}:{payload}']
    if set(expected) - set(constants):
        raise ValueError('missing required captured constant')
    return result


def make_backend(out):
    """Apply the Mesa initializer pass to a private copy of the existing backend."""
    base = ROOT / 'families'
    target = out / 'backend'
    target.mkdir()
    for name in ('misc_compile.py', 'misc_resource_lowering.h',
                 'misc_native_rt.h'):
        shutil.copyfile(base / name, target / name)
    original = (base / 'misc_backend.c').read_text()
    anchor = '   pan_preprocess_nir(nir,inputs.gpu_id);'
    if original.count(anchor) != 1:
        raise ValueError('base backend changed: initializer insertion point unknown')
    patched = original.replace(anchor,
        '   NIR_PASS(_,nir,nir_lower_variable_initializers,\n'
        '            nir_var_function_temp|nir_var_shader_temp);\n' + anchor)
    (target / 'misc_backend.c').write_text(patched)
    spec = importlib.util.spec_from_file_location('private_misc_compile',
                                                  target / 'misc_compile.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_reflection(meta):
    if meta['vertex_input'] != {
        'bindings': [{'binding': 0, 'buffer_index': 1, 'input_rate': 0,
                      'divisor': 1, 'stride': {'Static': 48}}],
        'attributes': [{'location': 0, 'binding': 0, 'format': 109, 'offset': 0},
                       {'location': 1, 'binding': 0, 'format': 97, 'offset': 32}],
        'pulled': [], 'variant_pulled': []}:
        raise ValueError('candidate vertex input contract changed')
    slots = {(key['stage'], key['class'], key['index']): value
             for key, value in meta['interface']['slots']}
    for key, size in ((('Vertex', 'Buffer', 2), 64),
                      (('Fragment', 'Buffer', 1), 168)):
        if slots[key]['Buffer']['window']['Bounded'] != {'start': 0, 'len': size}:
            raise ValueError(f'buffer window changed: {key}')
    if meta['graphics']['color_outputs'] != 1:
        raise ValueError('unexpected color outputs')
    if meta['graphics']['color_write_rules'] != [[0, 0x2222]] or \
            meta['graphics']['input_attachments'] or \
            meta['graphics']['snapshot_reads']:
        raise ValueError('actual fragment color/write/read contract changed')
    if meta['layout']['push_constants'] != [
        {'stages': 1, 'offset': 0, 'size': 4},
        {'stages': 16, 'offset': 64, 'size': 8}]:
        raise ValueError('push constant ABI changed')


def write_profile(out, vertex, fragment):
    header = out / 'profile.h'
    header.write_text('''\
/* Private metadata-authenticated 0185 host compilation profile. */
static const struct a5_resource_binding kvert_bindings[] = {{0,nir_descriptor_type_uniform_buffer}};
static const struct a5_resource_binding kfrag_bindings[] = {{1,nir_descriptor_type_uniform_buffer},{2,nir_descriptor_type_storage_buffer}};
static const struct a5_spec_value kvert_spec[] = {{0,64}};
static const struct a5_spec_value kfrag_spec[] = {{1,168}};
static const struct a5_texture_binding kvert_textures[] = {{0,0}};
static const struct a5_texture_binding kfrag_textures[] = {{0,0}};
static const struct a5_stage_profile kStages[] = {
 {UINT64_C(0x%016x),kvert_bindings,1,kvert_spec,1,kvert_textures,0,4},
 {UINT64_C(0x%016x),kfrag_bindings,2,kfrag_spec,1,kfrag_textures,0,72}
};
''' % (fnv(vertex.read_bytes()), fnv(fragment.read_bytes())))
    return header


def native_receipt(log, real_vertex=False):
    text = log.read_text()
    # Mesa's `MIDGARD_MESA_DEBUG=shaders` final NIR follows a unique marker.
    vertex_marker = 'MESA: info: shader: MESA_SHADER_VERTEX'
    if vertex_marker not in text:
        raise ValueError('no final vertex NIR in compiler log')
    vertex = text[text.rfind(vertex_marker):]
    vertex = vertex.split('block0: {', 1)[0]
    if ('VERT_ATTRIB_GENERIC0' not in vertex or
            'VERT_ATTRIB_GENERIC1' not in vertex or
            'VARYING_SLOT_VAR0' not in vertex or
            'VARYING_SLOT_POS' not in vertex):
        raise ValueError('candidate vertex I/O contract changed')
    if real_vertex and 'VARYING_SLOT_VAR1' in vertex:
        raise ValueError('real 0187 vertex unexpectedly reads/writes VAR1')
    vertex_ubos = re.findall(r'@load_ubo \(([^\n]+)', vertex)
    if not any('0x1' in load for load in vertex_ubos):
        raise ValueError('vertex matrix buffer no longer survives')
    if not any('0x200' in load for load in vertex_ubos) or not any(
            '0x210' in load for load in vertex_ubos):
        raise ValueError('vertex viewport constants no longer survive')
    marker = 'MESA: info: shader: MESA_SHADER_FRAGMENT'
    if marker not in text:
        raise ValueError('no final fragment NIR in compiler log')
    final = text[text.rfind(marker):]
    final = final.split('block0: {', 1)[0]
    loads = re.findall(r'@load_ubo \(([^\n]+)', final)
    if len(loads) != 1 or '0x0' not in loads[0] or '0x44' not in loads[0]:
        raise ValueError(f'fragment native UBO contract changed: {loads}')
    if re.search(r'@load_(?:global|ssbo|image)|@store_(?:global|ssbo|image)', final):
        raise ValueError('synthetic constant blob or other storage survives')
    if 'VARYING_SLOT_VAR0' not in final or 'FRAG_RESULT_DATA0' not in final:
        raise ValueError('fragment varying/output contract changed')
    if re.search(r'\bTEX(?:_|\.)|\btexture\(', final):
        raise ValueError('unexpected texture instruction')
    return {'fragment_live_ubo': [{'hardware_index': 0, 'byte_offset': 68,
                                    'role': 'ColorWriteRule'}],
            'fragment_live_varying': ['VAR0 float4'],
            'fragment_output': ['RT0 float4'],
            'fragment_declared_but_dead': ['Metal Buffer1 168 bytes',
                                           'SyntheticConstantBlob 16 bytes'],
            'candidate_vertex_live_inputs': [
                'location0 Float4 offset0', 'location1 Half4 offset32',
                'binding0 Metal Buffer1 stride48'],
            'candidate_vertex_live_uniforms': [
                'hardware UBO1 Metal Vertex Buffer2 64 byte matrix',
                'hardware UBO0 viewport scale +0x200, offset +0x210'],
            'candidate_vertex_outputs': ['POS', 'PSIZ', 'VAR0 float4'],
            'vertex_candidate': not real_vertex}


def validate_receipt(receipt_path, capture_path, metallib_path,
                     vertex_capture_path=None):
    """Allow an integrator to reject stale, substituted or partial host output."""
    receipt_path = Path(receipt_path)
    receipt = json.loads(receipt_path.read_text())
    capture_path = Path(capture_path)
    capture = json.loads(capture_path.read_text())
    profile = profile_for_capture(capture_path, vertex_capture_path)
    if (receipt['schema'] != 1 or
            receipt['profile_id'] != profile['profile_id'] or
            receipt['compiled_function'] != profile['compiled'] or
            receipt['captured_function'] != capture['function'] or
            not receipt['host_only'] or receipt['device_pair_verified']):
        raise ValueError('wrong generic profile receipt')
    if (receipt['capture_sha256'] != sha(capture_path) or
            receipt['captured_constants'] != capture['constants'] or
            receipt['named_constant_count'] != 58 or
            not captured_constants(capture_path)):
        raise ValueError('capture identity differs')
    if receipt['metallib_sha256'] != sha(Path(metallib_path)) or \
            receipt['metallib_sha256'] != PINNED_METALLIB_SHA256:
        raise ValueError('QuartzCore metallib identity differs')
    reflection = json.loads((receipt_path.parent / 'reflection.json').read_text())
    verify_reflection(reflection)
    if receipt['reflected_vertex_input'] != reflection['vertex_input'] or \
            receipt['reflected_layout'] != reflection['layout'] or \
            receipt['reflected_color_write_rules'] != reflection['graphics']['color_write_rules'] or \
            receipt['configured_vertex_packing0'] != PACKING0:
        raise ValueError('receipt differs from validated reflection')
    if receipt['vertex_function'] != profile['vertex']:
        raise ValueError('vertex function identity differs')
    if profile['profile_id'] == 602:
        vertex_capture = json.loads(Path(vertex_capture_path).read_text())
        if receipt['vertex_capture_sha256'] != sha(Path(vertex_capture_path)) or \
                receipt['vertex_captured_constants'] != vertex_capture['constants']:
            raise ValueError('real vertex capture differs')
    native = native_receipt(receipt_path.parent / 'midgard.log',
                            profile['profile_id'] == 602)
    if any(receipt[k] != value for k, value in native.items()):
        raise ValueError('receipt differs from native shader inspection')
    for stage in ('vert', 'frag'):
        item = receipt['stages'][stage]
        for kind, ext in (('spirv', 'spv'), ('midgard', 'midgard')):
            path = receipt_path.parent / f'{stage}.{ext}'
            if kind == 'spirv':
                path = receipt_path.parent / f"{profile['compiled']}.{stage}.spv"
            expected = ((profile['vertex_spirv_sha256'] if kind == 'spirv' else
                         PINNED_VERTEX['midgard']) if stage == 'vert' else
                        profile['fragment_spirv_sha256'] if kind == 'spirv' else
                        PINNED_FRAGMENT_NATIVE)
            if item[f'{kind}_bytes'] != path.stat().st_size or \
                    item[f'{kind}_sha256'] != sha(path) or \
                    item[f'{kind}_sha256'] != expected:
                raise ValueError(f'{stage} {kind} differs from pinned compiler result')
    return receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('capture', 'metallib', 'translator', 'validator', 'profile',
                 'mesa-build', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--vertex-capture', type=Path,
                   help='0187 actual vertex capture; enables strict profile 602')
    a = p.parse_args()
    out = a.output.resolve()
    if out == ROOT or ROOT in out.parents:
        p.error('generated artifacts must stay outside the checkout')
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        p.error('output must be empty to prevent stale compilation artifacts')
    constants = captured_constants(a.capture)
    captured_name = json.loads(a.capture.read_text())['function']
    profile = profile_for_capture(a.capture, a.vertex_capture)
    if sha(a.metallib) != PINNED_METALLIB_SHA256:
        p.error('this recipe requires the measured stock QuartzCore metallib')
    descriptor = out / 'packing0.json'
    descriptor.write_text(json.dumps(PACKING0, indent=2) + '\n')
    prefix = out / profile['compiled']
    meta_path = out / 'reflection.json'
    cmd = [str(a.translator), str(a.metallib), str(prefix) + '.spv',
           '--profile', str(a.profile), '--function', profile['vertex'],
           '--fragment', profile['compiled'], '--color-format',
           '0:BGRA8Unorm', '--vertex-descriptor', str(descriptor),
           '--emit-meta', str(meta_path), '--no-timeout'] + constants
    env = {**os.environ, 'METAL2VULKAN_SPIRV_VAL': str(a.validator)}
    run(cmd, out / 'translation.log', env)
    meta = json.loads(meta_path.read_text())
    verify_reflection(meta)
    stages = {stage: Path(str(prefix) + f'.{stage}.spv') for stage in
              ('vert', 'frag')}
    for stage, path in stages.items():
        run([str(a.validator), '--target-env', 'vulkan1.2',
             '--uniform-buffer-standard-layout', str(path)],
            out / f'{stage}-validation.log')
    backend = make_backend(out)
    config = write_profile(out, stages['vert'], stages['frag'])
    executable = out / 'midgard-compiler'
    if backend.compile_backend(a.mesa_build, config, executable,
                               out / 'backend-build.log'):
        raise RuntimeError('Mesa backend host build failed')
    native = {stage: out / f'{stage}.midgard' for stage in stages}
    env['MIDGARD_MESA_DEBUG'] = 'shaders'
    run([str(executable), str(stages['vert']), str(stages['frag']),
         str(native['vert']), str(native['frag'])], out / 'midgard.log', env)
    receipt = native_receipt(out / 'midgard.log', profile['profile_id'] == 602)
    info_lines = re.findall(
        r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) '
        r'tls=(\d+) wls=(\d+) attributes=(\d+) ubos=(\d+) samplers=(\d+)',
        (out / 'midgard.log').read_text())
    if len(info_lines) != 2:
        raise ValueError('missing or ambiguous Mesa shader info')
    names = ('bytes', 'first_tag', 'textures', 'work_regs', 'tls', 'wls',
             'attributes', 'ubos', 'samplers')
    infos = {stage: dict(zip(names, map(int, info_lines[index])))
             for index, stage in enumerate(('vert', 'frag'))}
    receipt.update(schema=1, profile_id=profile['profile_id'],
                   host_only=True, device_pair_verified=False,
                   captured_function=captured_name,
                   compiled_function=profile['compiled'],
                   vertex_function=profile['vertex'],
                   reason=profile['reason'],
                   named_constant_count=58,
                   capture_sha256=sha(a.capture), metallib_sha256=sha(a.metallib),
                   captured_constants=json.loads(a.capture.read_text())['constants'],
                   candidate_color_format='BGRA8Unorm (host assumption; not live captured)',
                   candidate_topology='triangle (host assumption; not live captured)',
                   reflected_vertex_input=meta['vertex_input'],
                   configured_vertex_packing0=PACKING0,
                   reflected_layout=meta['layout'],
                   reflected_color_write_rules=meta['graphics']['color_write_rules'],
                   vertex_capture_sha256=sha(a.vertex_capture) if a.vertex_capture else None,
                   vertex_captured_constants=json.loads(a.vertex_capture.read_text())['constants']
                       if a.vertex_capture else None,
                   stages={stage: {'spirv_sha256': sha(stages[stage]),
                                   'spirv_bytes': stages[stage].stat().st_size,
                                   'midgard_sha256': sha(native[stage]),
                                   'midgard_bytes': native[stage].stat().st_size,
                                   'native_info': infos[stage]}
                           for stage in stages})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    validate_receipt(out / 'receipt.json', a.capture, a.metallib,
                     a.vertex_capture)
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
