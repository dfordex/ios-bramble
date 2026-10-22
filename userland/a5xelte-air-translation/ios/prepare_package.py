#!/usr/bin/env python3
"""Build/sign the native runner and stage private iOS compiler artifacts.

No Apple shaders or generated machine code are included in this package.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verified_no_timeout_air(path, src):
    """Bind the unexecutable iOS Mach-O to the tested host CLI and patch."""
    manifest_path = path.parent / 'build-manifest.json'
    if not manifest_path.is_file():
        raise ValueError('translator is missing its no-timeout build manifest')
    manifest = json.loads(manifest_path.read_text())
    if (manifest.get('source_revision') != 'a2c440b8bcdcf20d34aa1694b61ae22c2a7ea68b' or
            manifest.get('patch_sha256') != sha(src / 'metal2vulkan-no-timeout.patch') or
            manifest.get('timeout_policy') !=
            'default 20s; explicit --no-timeout selects Budget::with_deadline(None)' or
            manifest.get('translation_algorithms_changed') is not False or
            manifest.get('spirv_validation_changed') is not False):
        raise ValueError('translator provenance lacks the verified no-timeout patch')
    ios = manifest['artifacts']['ios']
    host = manifest['artifacts']['host']
    if (ios['target'] != 'aarch64-apple-ios' or
            ios['sha256'] != sha(path) or ios['bytes'] != path.stat().st_size):
        raise ValueError('packaged iOS translator differs from patched build')
    host_path = path.parent / 'metal2vulkan-host'
    if (host['target'] != 'aarch64-apple-darwin' or
            host['sha256'] != sha(host_path) or host['bytes'] != host_path.stat().st_size):
        raise ValueError('paired host translator differs from patched build')
    help_text = subprocess.check_output([str(host_path), '--help'], text=True)
    if '  --no-timeout ' not in help_text:
        raise ValueError('patched host CLI does not support --no-timeout')
    return {'ios_sha256': ios['sha256'], 'host_sha256': host['sha256'],
            'patch_sha256': manifest['patch_sha256'],
            'source_revision': manifest['source_revision'],
            'no_timeout_cli_verified': True}


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
    ap.add_argument('--generic602', type=Path, required=True,
                    help='device Midgard backend for exact captured generic pair')
    ap.add_argument('--receipt602', type=Path, required=True)
    ap.add_argument('--fragment-capture602', type=Path, required=True)
    ap.add_argument('--vertex-capture602', type=Path, required=True)
    ap.add_argument('--metallib', type=Path, required=True)
    args = ap.parse_args()
    src = Path(__file__).resolve().parent
    air_proof = verified_no_timeout_air(args.air, src)
    out = args.output.resolve()
    if out == src or src in out.parents:
        ap.error('generated files must stay outside source')
    out.mkdir(parents=True, exist_ok=True)
    resources = out / 'a5shader'
    resources.mkdir(exist_ok=True)
    generic_recipe = load(src.parent / 'generic' / 'compile_0185.py', 'generic_recipe')
    receipt = generic_recipe.validate_receipt(args.receipt602,
        args.fragment_capture602, args.metallib, args.vertex_capture602)
    if receipt['profile_id'] != 602:
        raise ValueError('actual captured 0187/0186 pair required')
    for name, path in [('metal2vulkan', args.air), ('midgard-compile', args.midgard),
                       ('midgard-generic602', args.generic602),
                       ('spirv-val', args.validator)]:
        device_macho(path)
        shutil.copyfile(path, resources / name)
    runner = out / 'a5shader-compile'
    subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios16.0',
        '-mcpu=cortex-a53', '-march=armv8-a+crypto', '-fobjc-arc', '-fblocks',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
        str(src / 'a5shader_compile.m'), '-framework', 'Foundation', '-framework', 'IOKit', '-o', str(runner)], check=True)
    tool_names = ('metal2vulkan','midgard-compile','midgard-generic602','spirv-val')
    for path in [runner, *(resources / n for n in tool_names)]:
        device_macho(path)
        path.chmod(0o755)
        subprocess.run(['codesign', '--force', '--sign', '-', '--pagesize', '4096',
            '--identifier', 'com.orhunnx.a5shader.' + path.name,
            '--entitlements', str(src / 'compiler-entitlements.plist'), str(path)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
    verifier = src.parent.parent / 'a5mali-metal/StockMetalPlugin/verify_signature_pages.py'
    subprocess.run(['python3', str(verifier), str(runner),
        *(str(resources / n) for n in tool_names)],check=True)
    translation = load(src.parent / 'translate_stock_quartzcore.py', 'translation')
    pairs = {p: translation.PAIRS[p] for p in ('read_surf','downsample_4')}
    known = load(src.parent / 'test_compiler_profiles.py', 'known').EXPECTED
    for pair in pairs:
        pairs[pair]['expected_output'] = {s:{'bytes':known[pair][s][0], 'sha256':known[pair][s][2]}
            for s in ('vert','frag')}
    (resources / 'pairs.json').write_text(json.dumps(pairs, indent=2)+'\n')
    capture_vertex = json.loads(args.vertex_capture602.read_text())
    capture_fragment = json.loads(args.fragment_capture602.read_text())
    def captured_list(capture):
        return [{'name':name, 'type':item['type'],
                 'bytes':len(item['raw']) // 2, 'raw':item['raw']}
                for name,item in sorted(capture['constants'].items())]
    known602 = {
        'schema':1, 'profile_id':602,
        'metallib_sha256':receipt['metallib_sha256'],
        'vertex_function':receipt['vertex_function'],
        'fragment_function':receipt['compiled_function'],
        'vertex_constants':captured_list(capture_vertex),
        'fragment_constants':captured_list(capture_fragment),
        'configured_vertex_packing0':receipt['configured_vertex_packing0'],
        'reflected_vertex_input':receipt['reflected_vertex_input'],
        'reflected_layout':receipt['reflected_layout'],
        'reflected_color_write_rules':receipt['reflected_color_write_rules'],
        'spirv':{stage:{'bytes':receipt['stages'][stage]['spirv_bytes'],
                        'sha256':receipt['stages'][stage]['spirv_sha256']}
                 for stage in ('vert','frag')},
        'midgard':{stage:{'bytes':receipt['stages'][stage]['midgard_bytes'],
                          'sha256':receipt['stages'][stage]['midgard_sha256']}
                   for stage in ('vert','frag')},
    }
    (resources / 'generic602.json').write_text(json.dumps(known602, indent=2)+'\n')
    shutil.copyfile(args.profile, resources / 'profile.json')
    shutil.copyfile(src / 'compiler-launchdaemon.plist', out / 'compiler-launchdaemon.plist')
    # Keep provenance beside the payload. The device embedder has an exact
    # member allowlist and must not gain a new installed file by accident.
    (out.parent / (out.name + '-package-manifest.json')).write_text(json.dumps({
        'schema': 1, 'translator': air_proof,
        'runner_sha256': sha(runner),
        'generic602_midgard_sha256': sha(resources / 'midgard-generic602'),
        'generic602_contract_sha256': sha(resources / 'generic602.json'),
        'device_runtime_verified': False,
    }, indent=2) + '\n')
    print(json.dumps({'output':str(out),'device_runtime_verified':False,
        'bytes':sum(p.stat().st_size for p in out.rglob('*') if p.is_file())},indent=2))


if __name__ == '__main__':
    main()
