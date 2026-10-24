#!/usr/bin/env python3
"""Run production FragCoord lowering against the assertion-enabled Mesa release.

Use a native host Mesa build with the same standalone Panfrost compiler target
as misc_compile.py. Outputs and assertion-control logs remain outside Git.
"""
import argparse
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mesa-build', type=Path, required=True)
    parser.add_argument('--target', default='src/panfrost/a5_t720_copy_shader')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build, out = args.mesa_build.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parent
    commands = subprocess.check_output(['ninja', '-t', 'commands', args.target],
        cwd=build, text=True).splitlines()
    # Select the executable's final C source, then reuse the exact flags/libs.
    link = shlex.split(commands[-1])
    compiles = [shlex.split(c) for c in commands if ' -c ' in c and ' -o ' in c]
    cc = next(c for c in reversed(compiles)
              if c[c.index('-o') + 1] in link)
    old_object = cc[cc.index('-o') + 1]
    obj, executable = out / 'fragcoord-test.o', out / 'fragcoord-test'
    cc[cc.index('-c') + 1] = str(root / 'test_fragcoord_layout.c')
    cc[cc.index('-o') + 1] = str(obj)
    for flag in ('-MD', '-MQ', '-MF'):
        if flag in cc:
            i = cc.index(flag)
            del cc[i:i + (1 if flag == '-MD' else 2)]
    cc = [x for x in cc if not x.startswith('-DA5_FAMILY_CONFIG=')]
    cc += ['-Werror', f'-DA5_FAMILY_CONFIG="{root / "ios_602_profile.h"}"']
    subprocess.run(cc, cwd=build, check=True)
    link[link.index(old_object)] = str(obj)
    link[link.index('-o') + 1] = str(executable)
    nir_library = 'src/compiler/nir/libnir.a'
    vtn_library = 'src/compiler/spirv/libvtn.a'
    if vtn_library not in link:
        link.insert(link.index(nir_library), vtn_library)
    subprocess.run(link, cwd=build, check=True)
    with (out / 'result.log').open('w') as log:
        subprocess.run([str(executable)], stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    print((out / 'result.log').read_text(), end='')


if __name__ == '__main__':
    main()
