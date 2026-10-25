#!/usr/bin/env python3
"""Validate line topology and large output planes using real private shaders."""
import argparse
from pathlib import Path
import subprocess
from build_runtime_encoder import compile_runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mesa-build', 'registry', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    a = parser.parse_args()
    here = Path(__file__).resolve().parent
    out = a.output.resolve()
    if out == here or here in out.parents:
        parser.error('private output must remain outside source')
    out.mkdir(parents=True, exist_ok=True)
    objects = []
    for name in ('runtime_misc_encode', 'test_runtime_dynamic_format43', 'test_runtime_lines'):
        obj = out / (name + '.o')
        compile_runtime(a.mesa_build.resolve(), obj, 'host', here / (name + '.c'),
                        (a.registry.resolve(),))
        objects.append(str(obj))
    exe = out / 'test-lines'
    subprocess.run(['cc', *objects, '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
