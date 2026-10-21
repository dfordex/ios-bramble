#!/usr/bin/env python3
"""Build the SPIR-V stage compiler against a Mesa Panfrost build tree.

This reuses Mesa's existing a5_t720_copy_shader target flags/libraries. The
Mesa source/build trees and generated binary remain outside the repository.
"""
import pathlib
import shlex
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_local.py MESA_BUILD_DIR OUTPUT", file=sys.stderr)
        return 2
    build = pathlib.Path(sys.argv[1]).resolve()
    output = pathlib.Path(sys.argv[2]).resolve()
    source = pathlib.Path(__file__).with_name("spirv_pair_midgard.c").resolve()
    lines = subprocess.check_output(
        ["ninja", "-t", "commands", "src/panfrost/a5_t720_copy_shader"],
        cwd=build, text=True,
    ).splitlines()
    compile_line = next(
        line for line in lines
        if " -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c" in line
    )
    cc = shlex.split(compile_line)
    # This profile depends on validation remaining active; a release NDEBUG
    # build is rejected by the compiler source rather than silently skipping it.
    cc.append("-Werror")
    cc[cc.index("-c") + 1] = str(source)
    obj = output.with_suffix(".o")
    cc[cc.index("-o") + 1] = str(obj)
    for option in ("-MD", "-MQ", "-MF"):
        if option in cc:
            i = cc.index(option)
            del cc[i:i + (1 if option == "-MD" else 2)]
    subprocess.run(cc, cwd=build, check=True)
    ld = shlex.split(lines[-1])
    ld[ld.index("-o") + 1] = str(output)
    ld[ld.index("src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o")] = str(obj)
    vtn = pathlib.Path("src/compiler/spirv/libvtn.a")
    subprocess.run(["ninja", str(vtn)], cwd=build, check=True)
    ld.insert(ld.index("src/compiler/nir/libnir.a"), str(vtn))
    subprocess.run(ld, cwd=build, check=True)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
