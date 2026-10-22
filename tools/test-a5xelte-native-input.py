#!/usr/bin/env python3
"""Rebuild native client from repository patches and run its actual entry points."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REL = Path('iokit/Kernel/arm/A5XELTENativeClient.inc')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--kernel-source', type=Path, help='also require staged source to match')
    args = ap.parse_args()
    base = (ROOT / 'xnu/patches/0177-a5xelte-native-metal-runtime-queue.patch').read_text()
    section = base.split('+++ b/' + str(REL) + '\n', 1)[1].split('\n--- ', 1)[0]
    source = ''.join(line[1:] + '\n' for line in section.splitlines() if line.startswith('+'))
    with tempfile.TemporaryDirectory(prefix='a5-native-input-') as directory:
        directory = Path(directory)
        inc = directory / REL
        inc.parent.mkdir(parents=True)
        inc.write_text(source)
        patch = ROOT / 'xnu/patches/0190-a5xelte-prepare-native-ool-input.patch'
        subprocess.run(['patch', '-p1', '--batch', '--fuzz=0', '-i', str(patch)],
                       cwd=directory, check=True)
        if args.kernel_source:
            assert inc.read_bytes() == (args.kernel_source / REL).read_bytes(), 'staged source differs'
        binary = directory / 'native-input-test'
        subprocess.run(['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                        '-I' + str(ROOT / 'userland/a5xelte-gpu-translation'),
                        '-DA5_KERNEL_NATIVE_CLIENT="' + str(inc) + '"',
                        str(ROOT / 'tests/a5xelte-native-input.cpp'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()
