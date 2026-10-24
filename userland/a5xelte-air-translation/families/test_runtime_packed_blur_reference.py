#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Link packed blur oracle against the actual released Mesa format library."""
import argparse
from pathlib import Path
import shlex
import subprocess
from build_runtime_encoder import compile_runtime

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--mesa-build', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=True)
build = a.mesa_build.resolve()
obj = out / 'packed-reference.o'
compile_runtime(build, obj, 'host', Path(__file__).with_suffix('.c').resolve())
link = shlex.split(subprocess.check_output(
    ['ninja', '-t', 'commands', 'src/panfrost/a5_t720_copy_shader'], cwd=build,
    text=True).splitlines()[-1])
exe = out / 'packed-reference'
link[link.index('-o') + 1] = str(exe)
i = next(i for i, x in enumerate(link) if x.endswith('a5_t720_copy_shader.c.o'))
link[i] = str(obj)
subprocess.run(link, cwd=build, check=True)
subprocess.run([str(exe)], check=True)
