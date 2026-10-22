#!/usr/bin/env python3
"""Exercise the actual patched swap outcome state with host thread waiters.

This verifies the shared state/predicate; it does not emulate IOKit or validate
the phone's SwapWait call sequence.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REL = Path('iokit/Kernel/arm/SweetFramebuffer.cpp')


def state(source):
    return source.split('/* A5_SWAP_WAIT_STATE_BEGIN:', 1)[1].split(
        'enum A5SwapStatus', 1)[1].split('/* A5_SWAP_WAIT_STATE_END */', 1)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel-source', type=Path)
    args = parser.parse_args()
    patch = (ROOT / 'xnu/patches/0193-a5xelte-swap-wait-completion.patch').read_text()
    added = '\n'.join(line[1:] for line in patch.splitlines()
                      if line.startswith('+') and not line.startswith('+++'))
    body = state(added)
    if args.kernel_source:
        assert body == state((args.kernel_source / REL).read_text()), 'staged state differs'
    with tempfile.TemporaryDirectory(prefix='a5-swap-wait-') as directory:
        directory = Path(directory)
        header = directory / 'state.inc'
        header.write_text('enum A5SwapStatus' + body)
        binary = directory / 'test'
        subprocess.run(['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-pthread', '-fsanitize=address,undefined',
                        '-fno-omit-frame-pointer',
                        '-DA5_SWAP_STATE_HEADER="' + str(header) + '"',
                        str(ROOT / 'tests/a5xelte-swap-wait.cpp'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=15)


if __name__ == '__main__':
    main()
