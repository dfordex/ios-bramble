#!/usr/bin/env python3
"""Compile the real runtime emitter against an external released Mesa build.

No Mesa-generated headers or proprietary translated shaders are copied into Git.
"""
import argparse
from pathlib import Path
import shlex
import subprocess


def compile_runtime(mesa_build, output, target='ios', source=None, includes=()):
    source = source or Path(__file__).with_name('runtime_encode.c').resolve()
    commands = subprocess.check_output(
        ['ninja', '-t', 'commands', 'src/panfrost/a5_t720_copy_shader'],
        cwd=mesa_build, text=True).splitlines()
    command = shlex.split(next(c for c in commands
        if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in c))
    command[command.index('-c') + 1] = str(source)
    command[command.index('-o') + 1] = str(output.resolve())
    for flag in ('-MD', '-MQ', '-MF'):
        if flag in command:
            i = command.index(flag)
            del command[i:i + (1 if flag == '-MD' else 2)]
    command.append('-Werror')
    command.extend('-I' + str(p) for p in includes)
    if target == 'ios':
        sdk = subprocess.check_output(
            ['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        command = ['xcrun', '--sdk', 'iphoneos', 'clang',
            '-target', 'arm64-apple-ios16.0', '-mcpu=cortex-a53',
            '-march=armv8-a+crypto', '-isysroot', sdk] + command[1:]
    output.parent.mkdir(parents=True, exist_ok=True)
    from build_preload import build as build_preload
    preload_dir=output.parent.resolve() / 'preload-generated'
    build_preload(mesa_build.resolve(),preload_dir)
    command.append('-I'+str(preload_dir))
    subprocess.run(command, cwd=mesa_build, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mesa-build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--target', choices=('host', 'ios'), default='ios')
    parser.add_argument('--family', choices=('blur', 'misc', 'clear', 'path'), default='blur')
    parser.add_argument('--test-registry-dir', type=Path,
                        help='host-only: run structural tests with actual private compiled profiles')
    parser.add_argument('--legacy-fixture-manifest', type=Path,
                        help='authenticate device-tested family payloads for structural binding comparison')
    parser.add_argument('--test-clear-reference', action='store_true',
                        help='host clear family: compare to unmodified released Mesa pan_pack_color')
    args = parser.parse_args()
    if args.test_clear_reference and (args.family != 'clear' or args.target != 'host'):
        parser.error('--test-clear-reference requires --family clear --target host')
    if args.legacy_fixture_manifest and not args.test_registry_dir:
        parser.error('--legacy-fixture-manifest requires --test-registry-dir')
    if args.family == 'misc' and args.test_registry_dir and not args.legacy_fixture_manifest:
        parser.error('misc structural tests require --legacy-fixture-manifest')
    if args.test_registry_dir and args.target != 'host':
        parser.error('--test-registry-dir requires --target host')
    source = Path(__file__).with_name({'blur':'runtime_encode.c','misc':'runtime_misc_encode.c','clear':'runtime_clear.c','path':'runtime_path_encode.c'}[args.family]).resolve()
    compile_runtime(args.mesa_build.resolve(), args.output, args.target, source)
    if args.test_clear_reference:
        build = args.mesa_build.resolve()
        objects = [args.output]
        for source, suffix in ((Path(__file__).with_name('test_runtime_clear.c'), 'test'),
            (Path(__file__).with_name('test_runtime_clear_reference.c'), 'adapter'),
            (build.parent / 'mesa-26.2.4/src/panfrost/lib/pan_clear.c', 'mesa-reference')):
            obj = args.output.with_name(args.output.stem + '-' + suffix + '.o')
            compile_runtime(build, obj, 'host', source.resolve())
            objects.append(obj)
        link = shlex.split(subprocess.check_output(
            ['ninja','-t','commands','src/panfrost/a5_t720_copy_shader'],
            cwd=build, text=True).splitlines()[-1])
        test_binary = args.output.with_name(args.output.stem + '-test')
        link[link.index('-o') + 1] = str(test_binary.resolve())
        i = next(i for i, x in enumerate(link) if x.endswith('a5_t720_copy_shader.c.o'))
        link[i:i + 1] = [str(p.resolve()) for p in objects]
        subprocess.run(link, cwd=build, check=True)
        subprocess.run([str(test_binary.resolve())], check=True)
    if args.test_registry_dir:
        test_object = args.output.with_name(args.output.stem + '-test.o')
        test_binary = args.output.with_name(args.output.stem + '-test')
        compile_runtime(args.mesa_build.resolve(), test_object, 'host',
            Path(__file__).with_name({'misc':'test_runtime_misc.c','path':'test_runtime_path.c'}.get(args.family,'test_runtime_encode.c')).resolve(),
            (args.test_registry_dir.resolve(),))
        subprocess.run(['cc', str(args.output), str(test_object), '-o',
                        str(test_binary)], check=True)
        test_args = [str(test_binary.resolve())]
        if args.legacy_fixture_manifest:
            import hashlib, json
            doc = json.loads(args.legacy_fixture_manifest.read_text())
            fixtures = doc['cases'] if args.family == 'misc' else [next(
                c for c in doc['cases'] if c['name'] == 'downsample_8_frag_lph_bgra8')]
            for fixture in fixtures:
                payload = Path(fixture['payload'])
                if hashlib.sha256(payload.read_bytes()).hexdigest() != fixture['payload_sha256']:
                    raise ValueError('legacy fixture payload changed')
                if args.family == 'misc': test_args.append(fixture['name'])
                test_args.append(str(payload))
        subprocess.run(test_args, check=True)


if __name__ == '__main__':
    main()
