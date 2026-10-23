#!/usr/bin/env python3
"""Run actual loader copy/zero helpers against alignment, tail and guard oracles."""
from pathlib import Path
import os
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'shim/a5xelte/xnu_boot.c').read_text()
helpers = source[source.index('static void zero_bytes'):source.index('static void clean_bytes')]
test = r'''
#include <stdint.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
HELPERS
int main(void) {
    _Alignas(8) unsigned char s[9000], d[9000], want[9000];
    unsigned tests = 0;
    for (unsigned so = 0; so < 8; so++)
    for (unsigned off = 0; off < 8; off++)
    for (unsigned n = 0; n < 100; n++) {
        unsigned len = n < 97 ? n : (n == 97 ? 4095 : n == 98 ? 4096 : 8193);
        for (unsigned i = 0; i < sizeof s; i++) s[i] = (i * 37 + 13) & 255;
        memset(d, 0xa5, sizeof d); memcpy(want, d, sizeof d);
        memcpy(want + 16 + off, s + 16 + so, len);
        copy_bytes((uintptr_t)(d + 16 + off), (uintptr_t)(s + 16 + so), len);
        assert(!memcmp(d, want, sizeof d)); tests++;
        memset(d, 0xa5, sizeof d); memcpy(want, d, sizeof d);
        memset(want + 16 + off, 0, len);
        zero_bytes((uintptr_t)(d + 16 + off), len);
        assert(!memcmp(d, want, sizeof d)); tests++;
    }
    printf("%u actual helper alignment/tail/guard checks pass\n", tests);
}
'''.replace('HELPERS', helpers)
with tempfile.TemporaryDirectory(prefix='a5-loader-copy-') as directory:
    directory = Path(directory)
    cfile, binary = directory / 'test.c', directory / 'test'
    cfile.write_text(test)
    subprocess.run([os.environ.get('CC', 'clang'), '-O1', '-g',
                    '-fsanitize=address,undefined', str(cfile), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
