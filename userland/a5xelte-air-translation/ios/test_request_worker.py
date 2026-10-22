#!/usr/bin/env python3
"""Host test of one real 602 request through the native spool worker.

All stock inputs and generated shaders stay outside the checkout. The test
does not prove iOS execution or GPU submission.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def function(base, stage, capture):
    constants = [{'name': name, 'type': value['type'],
                  'bytes': len(value['raw']) // 2, 'raw': value['raw']}
                 for name, value in sorted(capture['constants'].items())]
    return dict(base, stage=stage, function=capture['function'],
                named_constants=constants, indexed_constants=[])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('translator', 'midgard', 'validator', 'profile', 'known',
                 'metallib', 'vertex-capture', 'fragment-capture', 'work-dir'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    work = a.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if any(work.iterdir()):
        p.error('--work-dir must be empty')
    tools = work / 'tools'
    tools.mkdir()
    for src, dst in ((a.translator, 'metal2vulkan'),
                     (a.midgard, 'midgard-generic602'),
                     (a.validator, 'spirv-val'),
                     (a.profile, 'profile.json'),
                     (a.known, 'generic602.json')):
        shutil.copy2(src, tools / dst)
    # A Homebrew validator may need real @rpath libraries. Its original lib
    # directory is copied to the relative path the bottle records.
    deps = subprocess.check_output(['otool', '-L', str(a.validator)], text=True)
    libs = work / 'lib'
    libs.mkdir()
    for line in deps.splitlines()[1:]:
        dependency = line.strip().split(' (', 1)[0]
        if not dependency.startswith(('@rpath/', '@loader_path/')):
            continue
        name = Path(dependency).name
        source = next((v for v in (a.validator.parent.parent / 'lib' / name,
                                  a.validator.parent / name) if v.is_file()), None)
        if source is None:
            raise RuntimeError(f'missing actual validator dependency {dependency}')
        shutil.copy2(source, libs / name)
    request_root = work / 'requests'
    request_root.mkdir(mode=0o1777)
    request_root.chmod(0o1777)
    uid = os.geteuid()
    uid_dir = request_root / str(uid)
    uid_dir.mkdir(mode=0o700)
    known = json.loads(a.known.read_text())
    base = {'schema': 1, 'kind': 'function', 'source_library': 'quartzcore',
            'metallib_sha256': known['metallib_sha256'], 'gpu_id': '07201000',
            'compiler_abi': 1}
    vertex = json.loads(a.vertex_capture.read_text())
    fragment = json.loads(a.fragment_capture.read_text())
    body = dict(base, kind='pipeline', owner_uid=uid,
                vertex=function(base, 'vertex', vertex),
                fragment=function(base, 'fragment', fragment),
                descriptor={'host_test': 1})
    request_id = sha(canonical(body))
    body['request_id'] = request_id
    request = uid_dir / f'{request_id}.request.json'
    request.write_bytes(canonical(body))
    request.chmod(0o600)
    source = Path(__file__).with_name('a5shader_compile.m')
    runner = work / 'a5shader-compile-host'
    cache, published = work / 'cache', work / 'compiled'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Os',
        '-DA5_SHADER_HOST_TEST=1', f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{cache}"', f'-DA5_TEST_LIBRARY="{a.metallib}"',
        f'-DA5_TEST_REQUESTS="{request_root}"',
        f'-DA5_TEST_PUBLISHED="{published}"', str(source),
        '-framework', 'Foundation', '-o', str(runner)], check=True)
    output = (work / 'service.log').open('w')
    service = subprocess.Popen([str(runner), '--serve'], stdout=output,
                               stderr=subprocess.STDOUT)
    try:
        result = published / request_id
        for _ in range(90):
            if (result.joinpath('receipt.json').exists() or service.poll() is not None):
                break
            time.sleep(1)
        if not result.joinpath('receipt.json').exists():
            raise AssertionError(f'no published 602 result: {work / "service.log"}')
        receipt = json.loads(result.joinpath('receipt.json').read_text())
        if (receipt['request_id'] != request_id or
                receipt['profile_id'] != 602 or
                receipt['stage_compiled'] is not True or
                receipt['pipeline_compatible'] is not False):
            raise AssertionError('compiled receipt identity differs')
        for stage in ('vertex', 'fragment'):
            info = receipt[stage]
            binary = result.joinpath(info['file']).read_bytes()
            if len(binary) != info['bytes'] or sha(binary) != info['sha256']:
                raise AssertionError(f'{stage} output differs from receipt')
        print(json.dumps({'host_end_to_end': True, 'device_verified': False,
                          'request_id': request_id, 'receipt': str(result / 'receipt.json'),
                          'vertex_sha256': receipt['vertex']['sha256'],
                          'fragment_sha256': receipt['fragment']['sha256']}, indent=2))
    finally:
        service.terminate()
        try:
            service.wait(timeout=5)
        except subprocess.TimeoutExpired:
            service.kill()
            service.wait()
        output.close()


if __name__ == '__main__':
    main()
