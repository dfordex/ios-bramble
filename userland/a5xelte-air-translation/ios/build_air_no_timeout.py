#!/usr/bin/env python3
"""Build the pinned translator plus only the explicit no-timeout CLI patch.

Creates an isolated detached Git worktree. The default CLI deadline remains
20 seconds; callers must explicitly pass --no-timeout. This does not disable
SPIR-V validation or change translator algorithms. Generated binaries are private.
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
PIN = 'a2c440b8bcdcf20d34aa1694b61ae22c2a7ea68b'


def capture(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--cargo', default='cargo')
    args = parser.parse_args()
    source, output = args.source.resolve(strict=True), args.output.resolve()
    cargo = shutil.which(args.cargo)
    if not cargo:
        raise RuntimeError('Cargo not found')
    if capture(['git', '-C', str(source), 'rev-parse', 'HEAD']) != PIN:
        raise RuntimeError('unexpected source revision')
    if capture(['git', '-C', str(source), 'status', '--porcelain', '--untracked-files=no']):
        raise RuntimeError('original tracked source must be clean')
    patch = HERE / 'metal2vulkan-no-timeout.patch'
    output.mkdir(parents=True, exist_ok=True)
    worktree = output / 'source'
    if worktree.exists():
        raise RuntimeError('choose a fresh output directory; source worktree already exists')
    subprocess.run(['git', '-C', str(source), 'worktree', 'add', '--detach', str(worktree), PIN], check=True)
    subprocess.run(['git', '-C', str(worktree), 'apply', '--unidiff-zero', '--check', str(patch)], check=True)
    subprocess.run(['git', '-C', str(worktree), 'apply', '--unidiff-zero', str(patch)], check=True)
    changed = capture(['git', '-C', str(worktree), 'diff', '--name-only'])
    if changed != 'crates/metal2vulkan/src/main.rs':
        raise RuntimeError('patch changed unexpected files')
    shutil.copy2(source / 'Cargo.lock', worktree / 'Cargo.lock')
    env = dict(os.environ)
    # Baseline release profile: no LTO/strip/codegen-unit optimization changes.
    for key in tuple(env):
        if key.startswith('CARGO_PROFILE_RELEASE_'):
            del env[key]
    env.update({
        'CARGO_TARGET_DIR': str(output / 'cargo-target'),
        'SOURCE_DATE_EPOCH': capture(['git', '-C', str(source), 'show', '-s', '--format=%ct']),
    })
    env['PATH'] = str(Path(cargo).parent) + os.pathsep + env.get('PATH', '')
    host = capture(['rustc', '-vV'], env=env).split('host: ', 1)[1].splitlines()[0]
    spec = importlib.util.spec_from_file_location('air_ios', HERE / 'build_air_translator.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    common = [cargo, 'build', '--manifest-path', str(worktree / 'Cargo.toml'), '--offline', '--locked',
              '--release', '--package', 'metal2vulkan', '--features', 'cli', '--bin', 'metal2vulkan']
    manifest = {'source_revision': PIN, 'patch_sha256': sha(patch),
                'cargo_lock_sha256': sha(worktree / 'Cargo.lock'),
                'timeout_policy': 'default 20s; explicit --no-timeout selects Budget::with_deadline(None)',
                'translation_algorithms_changed': False, 'spirv_validation_changed': False,
                'profile': 'upstream baseline release profile; no optimization overrides',
                'rustc': capture(['rustc', '-vV'], env=env), 'artifacts': {}}
    env['RUSTFLAGS'] = '-Dwarnings'
    subprocess.run(common + ['--target', host], env=env, check=True)
    compiled = output / 'cargo-target' / host / 'release' / 'metal2vulkan'
    host_artifact = output / 'metal2vulkan-host'
    shutil.copy2(compiled, host_artifact)
    if '--no-timeout' not in capture([str(host_artifact), '--help']):
        raise RuntimeError('built CLI does not expose the explicit no-timeout option')
    manifest['artifacts']['host'] = {'path': str(host_artifact), 'bytes': host_artifact.stat().st_size,
                                     'sha256': sha(host_artifact), 'target': host}
    (output / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Host artifact ready: ' + str(host_artifact), flush=True)
    env.update({'SDKROOT': capture(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path']),
                'IPHONEOS_DEPLOYMENT_TARGET': '16.0',
                'RUSTFLAGS': '-Dwarnings -C target-cpu=cortex-a53'})
    subprocess.run(common + ['--target', module.TARGET], env=env, check=True)
    compiled = output / 'cargo-target' / module.TARGET / 'release' / 'metal2vulkan'
    ios_artifact = output / 'metal2vulkan-ios'
    shutil.copy2(compiled, ios_artifact)
    manifest['artifacts']['ios'] = {**module.verify_ios(ios_artifact), 'path': str(ios_artifact),
                                    'target': module.TARGET, 'device_execution_verified': False}
    manifest['sdk_path'] = env['SDKROOT']
    (output / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
