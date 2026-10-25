#!/usr/bin/env python3
"""Replay an actual failing AIR request; its terminal receipt must be public
before the worker exits. Stock inputs/requests/logs stay in the private output.
This is host worker coverage, not a successful shader or physical GPU test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':')).encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ('tools', 'request', 'stock', 'output'):
        ap.add_argument('--' + arg, type=Path, required=True)
    args = ap.parse_args()
    root = args.output.resolve()
    if root.exists():
        ap.error('choose a fresh private output directory')
    root.mkdir(mode=0o700)
    for name, mode in (('requests', 0o1777), ('cache', 0o700), ('compiled', 0o755)):
        (root / name).mkdir(mode=mode)
        (root / name).chmod(mode)
    owner = root / 'requests' / str(os.geteuid())
    owner.mkdir(mode=0o700)
    original = json.loads(args.request.read_text())
    assert original['kind'] == 'function' and original['stage'] == 'fragment'
    original.pop('request_id', None)
    original['owner_uid'] = os.geteuid()
    key = hashlib.sha256(canonical(original)).hexdigest()
    request = dict(original, request_id=key)
    captured = owner / (key + '.request.json')
    captured.write_bytes(canonical(request))
    captured.chmod(0o600)
    runner = root / 'worker'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Os',
        '-Wall', '-Wextra', '-Werror', '-DA5_SHADER_HOST_TEST=1',
        f'-DA5_TEST_TOOLS="{args.tools.resolve()}"',
        f'-DA5_TEST_LIBRARY="{args.stock.resolve()}"',
        f'-DA5_TEST_CACHE="{root / "cache"}"',
        f'-DA5_TEST_REQUESTS="{root / "requests"}"',
        f'-DA5_TEST_PUBLISHED="{root / "compiled"}"',
        str(Path(__file__).with_name('a5shader_compile.m')), '-framework',
        'Foundation', '-o', str(runner)], check=True)
    with (root / 'worker.log').open('wb') as log:
        result = subprocess.run([str(runner), '--serve'], stdout=log,
                                stderr=subprocess.STDOUT, timeout=120)
    assert result.returncode != 0, 'the supplied real shader must fail compilation'
    status = json.loads((root / 'cache/request-status' / (key + '.json')).read_text())
    published = root / 'compiled' / key
    receipt = json.loads((published / 'receipt.json').read_text())
    assert status['status'] == 'failed' and status['request_id'] == key
    assert receipt['request_id'] == key and receipt['stage_compiled'] is False
    assert receipt['pipeline_compatible'] is False and receipt['function'] == request['function']
    assert receipt['error'] == status['reason']
    assert set(p.name for p in published.iterdir()) == {'receipt.json'}
    assert 'STAGE FAILED' in (root / 'worker.log').read_text()
    proof = {'worker_exit': result.returncode, 'private_status': 'failed',
             'public_terminal_receipt_before_exit': True, 'native_artifacts': 0,
             'request': str(captured), 'physical_gpu_execution': False}
    (root / 'result.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(proof, indent=2))


if __name__ == '__main__':
    main()
