#!/usr/bin/env python3
"""Compile the host-only downsample_4 v4 descriptor validator."""
import pathlib
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_downsample4_job_local.py MESA_BUILD_DIR OUTPUT", file=sys.stderr)
        return 2
    build = pathlib.Path(sys.argv[1]).resolve()
    source = build.parent / "mesa-26.2.4"
    output = pathlib.Path(sys.argv[2]).resolve()
    fixture = pathlib.Path(__file__).with_name("build_downsample4_job.c")
    subprocess.run([
        "clang", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
        "-Wno-unused-parameter",  # Mesa's generated print helpers omit these.
        "-I" + str(build / "src/panfrost"),
        "-I" + str(source / "src/panfrost"),
        "-I" + str(build / "src"),
        "-I" + str(source / "src"),
        "-I" + str(build / "include"),
        "-I" + str(source / "include"),
        str(fixture), "-o", str(output),
    ], check=True)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
