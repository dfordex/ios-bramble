#!/usr/bin/env python3
"""Build/sign the native runner and stage private iOS compiler artifacts.

No Apple shaders or generated machine code are included in this package.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def device_macho(path):
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError(f"truncated Mach-O: {path}")
    magic, cpu, subtype, kind, count = struct.unpack_from('<5I', data)
    if (magic, cpu, subtype, kind) != (0xfeedfacf, 0x100000c, 0, 2):
        raise ValueError(f"plain arm64 executable required: {path}")
    offset = 32
    platform = None
    for _ in range(count):
        cmd, size = struct.unpack_from('<2I', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("invalid load command")
        if cmd == 0x32:
            platform = struct.unpack_from('<I', data, offset + 8)[0]
        offset += size
    if platform != 2:
        raise ValueError(f"device iOS platform required: {path}")
    deps = subprocess.check_output(['xcrun', 'otool', '-L', str(path)], text=True)
    for line in deps.splitlines()[1:]:
        dep = line.strip().split(' ', 1)[0]
        if dep not in ('/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib',
                       '/System/Library/Frameworks/Foundation.framework/Foundation',
                       '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
                       '/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit',
                       '/System/Library/Frameworks/IOKit.framework/IOKit',
                       '/usr/lib/libobjc.A.dylib'):
            raise ValueError(f"unexpected iOS runtime dependency: {dep}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('air', type=Path)
    ap.add_argument('midgard', type=Path)
    ap.add_argument('validator', type=Path)
    ap.add_argument('profile', type=Path)
    ap.add_argument('output', type=Path)
    args = ap.parse_args()
    src = Path(__file__).resolve().parent
    out = args.output.resolve()
    if out == src or src in out.parents:
        ap.error('generated files must stay outside source')
    out.mkdir(parents=True, exist_ok=True)
    resources = out / 'a5shader'
    resources.mkdir(exist_ok=True)
    for name, path in [('metal2vulkan', args.air), ('midgard-compile', args.midgard),
                       ('spirv-val', args.validator)]:
        device_macho(path)
        shutil.copyfile(path, resources / name)
    runner = out / 'a5shader-compile'
    subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios16.0',
        '-mcpu=cortex-a53', '-march=armv8-a+crypto', '-fobjc-arc', '-fblocks',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
        str(src / 'a5shader_compile.m'), '-framework', 'Foundation', '-framework', 'IOKit', '-o', str(runner)], check=True)
    for path in [runner, *(resources / n for n in ('metal2vulkan','midgard-compile','spirv-val'))]:
        device_macho(path)
        path.chmod(0o755)
        subprocess.run(['codesign', '--force', '--sign', '-', '--pagesize', '4096',
            '--identifier', 'com.orhunnx.a5shader.' + path.name,
            '--entitlements', str(src / 'compiler-entitlements.plist'), str(path)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
    verifier = src.parent.parent / 'a5mali-metal/StockMetalPlugin/verify_signature_pages.py'
    subprocess.run(['python3', str(verifier), str(runner),
        *(str(resources / n) for n in ('metal2vulkan','midgard-compile','spirv-val'))],check=True)
    translation = load(src.parent / 'translate_stock_quartzcore.py', 'translation')
    pairs = {p: translation.PAIRS[p] for p in ('read_surf','downsample_4')}
    known = load(src.parent / 'test_compiler_profiles.py', 'known').EXPECTED
    for pair in pairs:
        pairs[pair]['expected_output'] = {s:{'bytes':known[pair][s][0], 'sha256':known[pair][s][2]}
            for s in ('vert','frag')}
    (resources / 'pairs.json').write_text(json.dumps(pairs, indent=2)+'\n')
    shutil.copyfile(args.profile, resources / 'profile.json')
    shutil.copyfile(src / 'compiler-launchdaemon.plist', out / 'compiler-launchdaemon.plist')
    print(json.dumps({'output':str(out),'device_runtime_verified':False,
        'bytes':sum(p.stat().st_size for p in out.rglob('*') if p.is_file())},indent=2))


if __name__ == '__main__':
    main()
