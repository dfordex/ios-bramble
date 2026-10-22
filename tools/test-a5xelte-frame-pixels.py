#!/usr/bin/env python3
"""Test the actual bounded pixel sampler shipped in the kernel patch."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REL = Path('iokit/Kernel/arm/A5XELTEFramePixels.h')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel-source', type=Path)
    args = parser.parse_args()
    patch = (ROOT / 'xnu/patches/0191-a5xelte-frame-hid-progress.patch').read_text()
    section = patch.split('+++ b/' + str(REL) + '\n', 1)[1].split('\n--- ', 1)[0]
    source = ''.join(line[1:] + '\n' for line in section.splitlines() if line.startswith('+'))
    with tempfile.TemporaryDirectory(prefix='a5-frame-pixels-') as directory:
        directory = Path(directory)
        header = directory / REL
        header.parent.mkdir(parents=True)
        header.write_text(source)
        extension = (ROOT / 'xnu/patches/0192-a5xelte-swap-ingress-and-full-pixels.patch').read_text()
        prefix = '--- a/' + str(REL) + '\n'
        diff = prefix + extension.split(prefix, 1)[1].split('\n--- ', 1)[0] + '\n'
        extra = directory / 'full-pixels.patch'
        extra.write_text(diff)
        subprocess.run(['patch', '-p1', '--batch', '--fuzz=0', '-i', str(extra)], cwd=directory, check=True)
        if args.kernel_source:
            assert header.read_bytes() == (args.kernel_source / REL).read_bytes(), 'staged header differs'
        binary = directory / 'test'
        subprocess.run(['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                        '-DA5_FRAME_PIXEL_HEADER="' + str(header) + '"',
                        str(ROOT / 'tests/a5xelte-frame-pixels.cpp'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()
