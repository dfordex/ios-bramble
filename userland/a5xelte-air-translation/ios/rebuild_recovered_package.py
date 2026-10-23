#!/usr/bin/env python3
"""Rebuild compiler tools while preserving verified installed 602–606 recipes.

The original private capture files need not survive. Every recovered recipe is
checked against committed source pins, retranslated from the pinned stock
library, validated and recompiled with the current backend before it is copied
unchanged. Generated Apple-derived artifacts stay in the private output tree.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess


HERE = Path(__file__).resolve().parent


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_stages(profile):
    generic = HERE.parent / 'generic'
    old = load(generic / 'compile_0185.py', 'old602')
    textured = load(generic / 'compile_0189.py', 'old603')
    variants = load(generic / 'compile_0200.py', 'old604605')
    alpha = load(generic / 'compile_0205.py', 'old606')
    if profile == 602:
        return {
            'vert': {'spirv_bytes': 3988, 'spirv_sha256': old.PINNED_REAL_VERTEX_SPIRV,
                     'midgard_bytes': 1808, 'midgard_sha256': old.PINNED_VERTEX['midgard']},
            'frag': {'spirv_bytes': 733380,
                     'spirv_sha256': old.PROFILES['fixed_frag_lph_cph']['fragment_spirv_sha256'],
                     'midgard_bytes': 848, 'midgard_sha256': old.PINNED_FRAGMENT_NATIVE}}
    if profile == 603:
        return textured.PIN
    return {'vert': variants.VS,
            'frag': (alpha.VARIANTS if profile == 606 else variants.VARIANTS)[profile]['frag']}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('recovered', 'air', 'midgard', 'backend', 'validator',
                 'host-backend', 'host-validator', 'metallib', 'output'):
        ap.add_argument('--' + name, type=Path, required=True)
    a = ap.parse_args()
    out = a.output.resolve()
    if HERE.parent in out.parents:
        ap.error('output must be private and outside the checkout')
    out.mkdir(exist_ok=True)
    resources = out / 'a5shader'
    resources.mkdir(exist_ok=True)
    proof = load(HERE / 'prepare_package.py', 'package_proof')
    air_proof = proof.verified_no_timeout_air(a.air, HERE)
    backend_proof = proof.verified_generic_backend(a.backend, HERE)
    host_air = a.air.parent / 'metal2vulkan-host'
    source_sha = sha(a.metallib)
    if source_sha != '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9':
        raise ValueError('stock QuartzCore source identity differs')
    env = dict(os.environ)
    env['METAL2VULKAN_SPIRV_VAL'] = str(a.host_validator.resolve())
    checks = []
    for profile in range(602, 607):
        original = a.recovered / f'generic{profile}.json'
        recipe = json.loads(original.read_text())
        expected = expected_stages(profile)
        if recipe['schema'] != 1 or recipe['profile_id'] != profile or \
                recipe['metallib_sha256'] != source_sha or \
                recipe['vertex_function'] != 'fixed_vert_lph_spc' or \
                recipe['fragment_function'] != 'fixed_frag_lph_cph':
            raise ValueError('recovered recipe identity differs')
        for suffix, pin in expected.items():
            native = recipe['midgard'][suffix]
            spirv = recipe['spirv'][suffix]
            if (native['bytes'], native['sha256'], spirv['bytes'], spirv['sha256']) != (
                    pin['midgard_bytes'], pin['midgard_sha256'],
                    pin['spirv_bytes'], pin['spirv_sha256']):
                raise ValueError(f'recovered {profile}/{suffix} differs from committed source pins')
        work = out / f'.verify-{profile}'
        work.mkdir(exist_ok=True)
        packing = work / 'packing.json'
        packing.write_text(json.dumps(recipe['configured_vertex_packing0']))
        command = [str(host_air), str(a.metallib.resolve()), str(work / 'shader.spv'),
            '--profile', str((a.recovered / 'profile.json').resolve()),
            '--function', recipe['vertex_function'], '--fragment', recipe['fragment_function'],
            '--color-format', '0:BGRA8Unorm', '--vertex-descriptor', str(packing),
            '--emit-meta', str(work / 'reflection.json'), '--no-timeout']
        for item in recipe['fragment_constants']:
            kind = {49: 'uchar', 51: 'uchar3', 53: 'bool'}[item['type']]
            values = bytes.fromhex(item['raw'])
            value = ','.join(('true' if x else 'false') if kind == 'bool' else str(x)
                             for x in values)
            command += ['--constant', f'{item["name"]}:{kind}:{value}']
        with (work / 'air.log').open('w') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env, check=True)
        if 'spirv-val vulkan1.2: PASS' not in (work / 'air.log').read_text():
            raise ValueError('actual SPIR-V validation did not run')
        metadata = json.loads((work / 'reflection.json').read_text())
        if metadata['vertex_input'] != recipe['reflected_vertex_input'] or \
                metadata['layout'] != recipe['reflected_layout'] or \
                metadata['graphics']['color_write_rules'] != recipe['reflected_color_write_rules']:
            raise ValueError('recovered layout differs from actual stock translation')
        with (work / 'midgard.log').open('w') as log:
            subprocess.run([str(a.host_backend.resolve()), str(work / 'shader.vert.spv'),
                str(work / 'shader.frag.spv'), str(work / 'vert.midgard'), str(work / 'frag.midgard')],
                stdout=log, stderr=subprocess.STDOUT, check=True)
        for suffix, pin in expected.items():
            spirv, native = work / f'shader.{suffix}.spv', work / f'{suffix}.midgard'
            if spirv.stat().st_size != pin['spirv_bytes'] or sha(spirv) != pin['spirv_sha256'] or \
                    native.stat().st_size != pin['midgard_bytes'] or sha(native) != pin['midgard_sha256']:
                raise ValueError(f'actual {profile}/{suffix} recompilation differs from pinned recipe')
        shutil.copyfile(original, resources / original.name)
        checks.append({'profile': profile, 'recipe_sha256': sha(original),
                       'actual_spirv_val': True, 'actual_native_pins_matched': True})
    for name in ('profile.json', 'pairs.json'):
        shutil.copyfile(a.recovered / name, resources / name)
    # The old two-pair metadata is authored in the source tree too.
    translation = load(HERE.parent / 'translate_stock_quartzcore.py', 'translation_pairs')
    compiler = load(HERE.parent / 'test_compiler_profiles.py', 'compiler_pairs')
    expected_pairs = {name: dict(translation.PAIRS[name], expected_output={
        s: {'bytes': compiler.EXPECTED[name][s][0], 'sha256': compiler.EXPECTED[name][s][2]}
        for s in ('vert', 'frag')}) for name in ('read_surf', 'downsample_4')}
    if json.loads((resources / 'pairs.json').read_text()) != json.loads(json.dumps(expected_pairs)):
        raise ValueError('recovered two-pair recipes differ from source')
    for source, name in ((a.air, 'metal2vulkan'), (a.midgard, 'midgard-compile'),
                         (a.backend, 'midgard-generic602'), (a.validator, 'spirv-val')):
        proof.device_macho(source)
        shutil.copyfile(source, resources / name)
    runner = out / 'a5shader-compile'
    subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios16.0',
        '-mcpu=cortex-a53', '-march=armv8-a+crypto', '-fobjc-arc', '-fblocks',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
        str(HERE / 'a5shader_compile.m'), '-framework', 'Foundation', '-framework', 'IOKit',
        '-o', str(runner)], check=True)
    executables = [runner, *(resources / n for n in
        ('metal2vulkan', 'midgard-compile', 'midgard-generic602', 'spirv-val'))]
    for path in executables:
        proof.device_macho(path)
        path.chmod(0o755)
        subprocess.run(['codesign', '--force', '--sign', '-', '--pagesize', '4096',
            '--identifier', 'com.orhunnx.a5shader.' + path.name, '--entitlements',
            str(HERE / 'compiler-entitlements.plist'), str(path)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
    subprocess.run([str(Path(os.sys.executable)),
        str(HERE.parent.parent / 'a5mali-metal/StockMetalPlugin/verify_signature_pages.py'),
        *(str(path) for path in executables)], check=True)
    shutil.copyfile(HERE / 'compiler-launchdaemon.plist', out / 'compiler-launchdaemon.plist')
    result = {'schema': 1, 'translator': air_proof, 'generic_backend': backend_proof,
        'runner_sha256': sha(runner), 'recovered_recipes_recompiled': checks,
        'validator_source': 'unchanged installed iOS validator, signature reverified and resigned',
        'device_runtime_verified': False}
    for profile in range(602, 607):
        result[f'generic{profile}_contract_sha256'] = sha(resources / f'generic{profile}.json')
    result['generic602_midgard_sha256'] = sha(resources / 'midgard-generic602')
    (out.parent / (out.name + '-package-manifest.json')).write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({'output': str(out), 'recipe_profiles_verified': 5,
        'signed_executables': len(executables), 'device_runtime_verified': False}, indent=2))


if __name__ == '__main__':
    main()
