#!/usr/bin/env python3
"""Compile eight actual QuartzCore blur pairs to checked SPIR-V and T720 code.

Shader inputs, outputs and logs stay in the caller's private output directory.
This is a bounded offline compilation recipe, not compositor/runtime support.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time

HERE = Path(__file__).resolve().parent
FRAGMENTS = ['downsample_8_frag_lph'] + [
    f'narrow_blur_{n}_frag_lph' for n in (7, 11, 15, 19, 23, 27)
] + ['single_pass_blur_3_lph']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fnv(path):
    value = 0xcbf29ce484222325
    for byte in path.read_bytes():
        value = ((value ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    return f'{value:016x}'


def load_contract():
    path = HERE.parent / 'translate_stock_quartzcore.py'
    spec = importlib.util.spec_from_file_location('stock_contract', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_backend(build, output):
    lines = subprocess.check_output(['ninja', '-t', 'commands',
        'src/panfrost/a5_t720_copy_shader'], cwd=build, text=True).splitlines()
    line = next(line for line in lines if
                ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in line)
    cc = shlex.split(line)
    cc.append('-Werror')
    cc[cc.index('-c') + 1] = str(HERE / 'blur_pair_midgard.c')
    obj = output.with_suffix('.o')
    cc[cc.index('-o') + 1] = str(obj)
    for flag in ('-MD', '-MQ', '-MF'):
        if flag in cc:
            index = cc.index(flag)
            del cc[index:index + (1 if flag == '-MD' else 2)]
    subprocess.run(cc, cwd=build, check=True)
    ld = shlex.split(lines[-1])
    ld[ld.index('-o') + 1] = str(output)
    ld[ld.index('src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o')] = str(obj)
    vtn = 'src/compiler/spirv/libvtn.a'
    subprocess.run(['ninja', vtn], cwd=build, check=True)
    ld.insert(ld.index('src/compiler/nir/libnir.a'), vtn)
    subprocess.run(ld, cwd=build, check=True)


def check_attachment_meta(meta, expected, color_format, contract):
    if color_format == 'BGRA8Unorm':
        return contract.check_meta(meta, expected)
    # The shared helper checks BGRA's attachment as well as common resources.
    # Prove the actual RGBA16Float attachment first; reuse only its unaffected
    # resource/push/specialization checks on a private metadata copy.
    graphics = meta['graphics']
    if graphics['color_attachments'] != [{'format': 97, 'write_mask': 15, 'blend': None}] or \
       graphics['rasterization_samples'] != 1 or graphics['color_write_rules'] != [[0, 0x3333]]:
        raise ValueError('changed RGBA16Float single-sample attachment ABI')
    common = copy.deepcopy(meta)
    common['graphics']['color_attachments'][0]['format'] = 44
    common['graphics']['color_write_rules'] = [[0, 0x2222]]
    result = contract.check_meta(common, expected)
    result.update(color_format='RGBA16Float', color_write_rule='0x3333')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('metallib', 'translator', 'spirv-val', 'profile', 'mesa-build', 'inventory', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    for name, value in vars(args).items():
        setattr(args, name, value.resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    contract = load_contract()
    backend = args.output / 'blur-pair-midgard'
    build_backend(args.mesa_build, backend)
    descriptor = args.output / 'vertex-descriptor.json'
    descriptor.write_text(json.dumps(contract.DOWNSAMPLE_4_VERTEX_DESCRIPTOR, indent=2) + '\n')
    env = dict(os.environ, METAL2VULKAN_SPIRV_VAL=str(args.spirv_val))
    inventory = json.loads(args.inventory.read_text())
    manifest = {'scope': 'host compilation only; no device rendering proof',
                'metallib_sha256': sha(args.metallib), 'profile_sha256': sha(args.profile),
                'translator_sha256': sha(args.translator), 'backend_sha256': sha(backend),
                'backend_source_sha256': sha(HERE / 'blur_pair_midgard.c'),
                'recipe_sha256': sha(Path(__file__)),
                'validator_sha256': sha(args.spirv_val),
                'validator_version': subprocess.check_output([str(args.spirv_val), '--version'], text=True),
                'mesa_release': '26.2.4', 'pairs': [],
                'pipeline_rows': []}
    if inventory['quartzcore_uuid'] != '9e40b2eb-260c-3af1-ae45-a1a551a8c1b9':
        raise ValueError('format-table mapping requires the reviewed QuartzCore UUID')
    selected_rows = [row for row in inventory['direct_fast_profiles'] if
                     row['vertex'] == 'downsample_blur_vert_lph' and row['fragment'] in FRAGMENTS]
    if any(not row['pipeline'].startswith(('PBGR', 'PRGhA')) for row in selected_rows):
        raise ValueError('unknown attachment prefix requires its actual format-table mapping')
    manifest['pipeline_rows'] = [{**row, 'color_format':
        'RGBA16Float' if row['pipeline'].startswith('PRGhA') else 'BGRA8Unorm',
        'runtime_pipeline_verified': False,
        'attachment_mapping_verified': True,
        'attachment_mapping_evidence': ('UUID9e40b2eb-260c-3af1-ae45-a1a551a8c1b9 MetalContext::MTLPixelFormat_codes@0x1d5b46d78 index115=RGhA (Metal RGBA16Float)'
            if row['pipeline'].startswith('PRGhA') else 'existing bounded BGRA8 attachment contract')}
        for row in selected_rows]
    profiles = [(fragment, 'BGRA8Unorm') for fragment in FRAGMENTS] + [
        ('narrow_blur_23_frag_lph', 'RGBA16Float')]
    for fragment, color_format in profiles:
        entry = {'vertex': 'downsample_blur_vert_lph', 'fragment': fragment,
                 'attachment_format': color_format, 'runtime_verified': False}
        manifest['pairs'].append(entry)
        directory = args.output / (fragment if color_format == 'BGRA8Unorm' else fragment + '_' + color_format)
        directory.mkdir(exist_ok=True)
        rows = [row for row in inventory['direct_fast_profiles'] if
                row['vertex'] == entry['vertex'] and row['fragment'] == fragment and
                (row['pipeline'].startswith('PRGhA')) == (color_format == 'RGBA16Float')]
        entry['warmup_rows'] = [row['row'] for row in rows]
        entry['warmup_attachment_mapping_verified'] = True
        try:
            if not rows or any(row['constant_values'] is not None for row in rows):
                raise ValueError('missing actual unspecialized warmup contract')
            entry['air_function_constants'] = None
            meta_path = directory / 'meta.json'
            command = [str(args.translator), str(args.metallib), str(directory / 'pair.spv'),
                       '--function', entry['vertex'], '--fragment', fragment,
                       '--profile', str(args.profile), '--color-format', '0:' + color_format,
                       '--vertex-descriptor', str(descriptor), '--emit-meta', str(meta_path),
                       '--no-timeout']
            started = time.monotonic()
            result = subprocess.run(command, text=True, capture_output=True, env=env)
            entry['air_seconds'] = time.monotonic() - started
            (directory / 'air-translation.log').write_text(result.stdout + result.stderr)
            if result.returncode or '; spirv-val ' not in result.stdout or ': PASS' not in result.stdout:
                raise ValueError(f'AIR translation/real validator failed: exit{result.returncode}')
            meta = json.loads(meta_path.read_text())
            expected = copy.deepcopy(contract.PAIRS['downsample_4'])
            window = 32 if fragment == 'downsample_8_frag_lph' else 82
            expected['buffer_windows'][2] = ('UniformWords', window)
            entry['io_abi'] = check_attachment_meta(meta, expected, color_format, contract)
            entry['vertex_input'] = meta['vertex_input']
            entry['precision_notes'] = [stage['precision_notes'] for stage in meta['stages']]
            for slot, interface in meta['interface']['slots']:
                if slot['class'] == 'Buffer' and interface['Buffer']['window']['Bounded']['start'] != 0:
                    raise ValueError('nonzero buffer binding offset requires a new contract')
            # These are resource-range/sampler specializations, not fabricated
            # Metal function constants. Every reflected byte remains available.
            entry['native_binding'] = {'stage_ubo0_byte_offsets': {'texture_levels': 0, 'width': 4,
                'height': 8, 'sampler_min_max_bias': 16, 'vertex_push': 0, 'fragment_push': 64},
                'ubo1_vertex_buffer2_bytes': 64, 'ubo2_vertex_buffer3_bytes': 16,
                'ubo3_fragment_buffer1_bytes': window, 'ubo4_fragment_buffer6_bytes': 2,
                'texture_index': 0, 'sampler_index': 0,
                'sampler': 'normalized nearest; sampler-state specialization0',
                'viewport': [1080, 1920], 'base_vertex': 0, 'color': color_format}
            vert, frag = directory / 'pair.vert.spv', directory / 'pair.frag.spv'
            for name, path in [('vert', vert), ('frag', frag)]:
                entry[name + '_spirv'] = {'bytes': path.stat().st_size, 'sha256': sha(path), 'fnv1a64': fnv(path)}
            command = [str(backend), str(vert), str(frag), str(directory / 'pair.vert.midgard'),
                       str(directory / 'pair.frag.midgard'), fnv(vert), fnv(frag), str(window)]
            if color_format == 'RGBA16Float':
                command.append('rgba16f')
            started = time.monotonic()
            result = subprocess.run(command, text=True, capture_output=True)
            entry['midgard_seconds'] = time.monotonic() - started
            (directory / 'midgard.log').write_text(result.stdout + result.stderr)
            if result.returncode:
                raise ValueError(f'Panfrost backend failed: exit{result.returncode}; see private midgard.log')
            reports = re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+) attributes=(\d+) ubos=(\d+) samplers=(\d+)', result.stdout)
            if len(reports) != 2:
                raise ValueError('missing exact compiler stage-info reports')
            for name, report in zip(('vert', 'frag'), reports):
                path = directory / ('pair.' + name + '.midgard')
                info = dict(zip(('bytes', 'first_tag', 'textures', 'work_regs', 'tls', 'wls', 'attributes', 'ubos', 'samplers'), map(int, report)))
                if path.stat().st_size != info['bytes'] or not info['bytes']:
                    raise ValueError('missing/invalid native shader output')
                entry[name + '_midgard'] = {**info, 'sha256': sha(path), 'fnv1a64': fnv(path)}
            if color_format == 'RGBA16Float':
                entry['native_packing_verified'] = True
                entry['native_packing'] = 'Mesa26.2.4 pan_nir_lower_framebuffer RAW64 pack32_2x16 RG/BA'
                entry['native_packing_helper_sha256'] = sha(HERE / 'misc_native_rt.h')
            entry['status'] = 'compiled'
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
            entry['status'] = 'failed'
            entry['reason'] = str(error)
        (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print(fragment + '/' + color_format + ': ' + entry['status'] + (' ' + entry['reason'] if 'reason' in entry else ''), flush=True)
    count = sum(entry['status'] == 'compiled' for entry in manifest['pairs'])
    print(f'Genuine AIR -> validated SPIR-V -> T720: {count}/{len(profiles)} attachment profiles; host only')
    return 0 if count == len(profiles) else 1


if __name__ == '__main__':
    raise SystemExit(main())
