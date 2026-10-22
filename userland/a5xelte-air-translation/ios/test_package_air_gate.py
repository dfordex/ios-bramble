#!/usr/bin/env python3
"""Reject an iOS translator whose paired CLI lacks the explicit no-timeout flag.

Requires a real private output from build_air_no_timeout.py. Copies only the
manifest/host tool into a temporary test directory; the device binary is hard
linked or copied there. No binary or stock shader is stored in the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from prepare_package import verified_no_timeout_air


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rejected(path, source, label):
    try:
        verified_no_timeout_air(path, source)
    except (ValueError, FileNotFoundError, OSError):
        print(f'PASS reject {label}')
        return
    raise AssertionError(f'accepted incompatible translator: {label}')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('patched_build', type=Path)
    p.add_argument('--old-translator', type=Path,
                   help='optional earlier iOS binary without a matching patch manifest')
    a = p.parse_args()
    source = Path(__file__).resolve().parent
    build = a.patched_build.resolve(strict=True)
    original = build / 'metal2vulkan-ios'
    verified_no_timeout_air(original, source)
    print('PASS patched host/iOS pair and CLI')
    with tempfile.TemporaryDirectory(prefix='a5shader-air-gate-') as directory:
        temp = Path(directory)
        ios = temp / 'metal2vulkan-ios'
        try:
            ios.hardlink_to(original)
        except OSError:
            shutil.copy2(original, ios)
        host = temp / 'metal2vulkan-host'
        shutil.copy2(build / 'metal2vulkan-host', host)
        manifest_path = temp / 'build-manifest.json'
        baseline = json.loads((build / 'build-manifest.json').read_text())

        def case(label, alter):
            candidate = json.loads(json.dumps(baseline))
            alter(candidate)
            manifest_path.write_text(json.dumps(candidate))
            rejected(ios, source, label)

        case('missing patch proof', lambda m: m.pop('patch_sha256'))
        case('wrong iOS SHA', lambda m: m['artifacts']['ios'].update(sha256='0'*64))
        case('wrong host SHA', lambda m: m['artifacts']['host'].update(sha256='0'*64))
        host.write_text('#!/bin/sh\necho "usage: metal2vulkan --timeout-ms N"\n')
        host.chmod(0o755)

        def fake_cli(m):
            m['artifacts']['host']['sha256'] = sha(host)
            m['artifacts']['host']['bytes'] = host.stat().st_size
        case('CLI without --no-timeout', fake_cli)
        manifest_path.unlink()
        rejected(ios, source, 'missing manifest')
    if a.old_translator:
        rejected(a.old_translator.resolve(strict=True), source,
                 'old translator input')


if __name__ == '__main__':
    main()
