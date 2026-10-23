#!/usr/bin/env python3
"""Run actual loader copy/zero helpers against alignment, tail and guard oracles."""
from pathlib import Path
import os
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'shim/a5xelte/xnu_boot.c').read_text()
helpers = source[source.index('static void zero_bytes'):source.index('static void clean_bytes')]
header = (Path(__file__).resolve().parents[1] / 'shim/a5xelte/watchdog.h').read_text()
reload = header[header.index('static inline void a5_watchdog_reload'):header.index('static inline void a5_watchdog_keepalive')]
test = r'''
#include <stdint.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
static unsigned kicks;
static void a5_watchdog_keepalive(void) { kicks++; }
RELOAD
HELPERS
int main(void) {
    volatile uint32_t regs[4];
    for (unsigned count = 0; count < 65536; count++) {
        regs[0] = 0x8021; regs[1] = count | 0xabcd0000U;
        regs[2] = 0x1234; regs[3] = 0x5678;
        a5_watchdog_reload(regs);
        assert(regs[0] == 0x8021 && regs[1] == (count | 0xabcd0000U));
        assert(regs[2] == (count ? count : 0xffffU) && regs[3] == 0x5678);
    }
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
    assert(kicks);
    printf("%u actual helper alignment/tail/guard checks and 65536 reload cases pass\n", tests);
}
'''.replace('HELPERS', helpers).replace('RELOAD', reload)
with tempfile.TemporaryDirectory(prefix='a5-loader-copy-') as directory:
    directory = Path(directory)
    cfile, binary = directory / 'test.c', directory / 'test'
    cfile.write_text(test)
    subprocess.run([os.environ.get('CC', 'clang'), '-O1', '-g',
                    '-fsanitize=address,undefined', str(cfile), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
