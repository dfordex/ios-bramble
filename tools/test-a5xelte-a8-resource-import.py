#!/usr/bin/env python3
"""Exercise the actual kernel format/layout helpers without kernel headers."""
import argparse
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('kernel', type=Path)
args = p.parse_args()
header = (args.kernel / 'iokit/Kernel/arm/A5XELTEGPUResources.h').read_text()
start = header.index('static inline uint32_t a5g3d_resource_format_bytes')
end = header.index('/* A retained IOSurface.', start)
test = r'''
#include <cassert>
#include <cstdint>
int main() {
    assert(a5g3d_resource_format_bytes(0x41303038) == 1);
    assert(a5g3d_resource_format_bytes(0x4c303038) == 1);
    assert(!a5g3d_resource_format_bytes(1)); // Metal enum is not import identity.
    assert(a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 576, 64, 176128));
    assert(!a5g3d_resource_linear_layout(0x41303038, 2, 576, 301, 1152, 64, 352256));
    assert(!a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 575, 64, 176128));
    assert(!a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 576, 64, 173439));
    assert(a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 576, 64, 173440));
    assert(!a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 576, UINT32_MAX, 176128));
    assert(!a5g3d_resource_linear_layout(0x41303038, 1, 0, 301, 576, 64, 176128));
    assert(!a5g3d_resource_linear_layout(0x41303038, 1, 576, 301, 576, 64, 0x2000001));
}
'''
with tempfile.TemporaryDirectory(prefix='a5-a8-resource-') as temp:
    source = Path(temp) / 'test.cpp'
    source.write_text('#include <cstdint>\n' + header[start:end] + test)
    binary = Path(temp) / 'test'
    subprocess.run(['clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('A8 kernel import: distinct identity, exact live span, byte count, short allocation and overflow checks PASS')
