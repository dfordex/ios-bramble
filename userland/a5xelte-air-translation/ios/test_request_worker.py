#!/usr/bin/env python3
"""Host test of strict requests and idempotent status handling in the worker.

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


def enqueue(uid_dir, body):
    key = sha(canonical(body))
    request = dict(body, request_id=key)
    path = uid_dir / f'{key}.request.json'
    path.write_bytes(canonical(request))
    path.chmod(0o600)
    return key


def wait_for(path, service, seconds=90):
    for _ in range(seconds):
        if path.exists() or service.poll() is not None:
            break
        time.sleep(1)
    if not path.exists():
        raise AssertionError(f'expected output missing: {path}; exit={service.poll()}')


def stop(service):
    service.terminate()
    try:
        service.wait(timeout=5)
    except subprocess.TimeoutExpired:
        service.kill()
        service.wait()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('translator', 'midgard', 'validator', 'profile', 'known',
                 'metallib', 'fragment-capture', 'work-dir'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--vertex-capture', type=Path)
    p.add_argument('--other-known', type=Path, required=True)
    p.add_argument('--additional-known', type=Path, action='append', default=[],
                   help='remaining installed exact generic contracts')
    p.add_argument('--stale-fragment', type=Path,
                   help='old 976-byte pixel-coordinate profile 603 shader')
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
                     (a.known, f'generic{json.loads(a.known.read_text())["profile_id"]}.json'),
                     (a.other_known, f'generic{json.loads(a.other_known.read_text())["profile_id"]}.json'),
                     *[(item, f'generic{json.loads(item.read_text())["profile_id"]}.json')
                       for item in a.additional_known]):
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
    if known['profile_id'] == 602:
        if a.vertex_capture is None:
            p.error('--vertex-capture required for 602')
        vertex = json.loads(a.vertex_capture.read_text())
    else:
        vertex = {'function':known['vertex_function'],
                  'constants':{c['name']:{'type':c['type'],'raw':c['raw']}
                               for c in known['vertex_constants']}}
    fragment = json.loads(a.fragment_capture.read_text())
    body = dict(base, kind='pipeline', owner_uid=uid,
                vertex=function(base, 'vertex', vertex),
                fragment=function(base, 'fragment', fragment),
                descriptor={'host_test': 1})
    source = Path(__file__).with_name('a5shader_compile.m')
    runner = work / 'a5shader-compile-host'
    cache, published = work / 'cache', work / 'compiled'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Os',
        '-DA5_SHADER_HOST_TEST=1', f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{cache}"', f'-DA5_TEST_LIBRARY="{a.metallib}"',
        f'-DA5_TEST_REQUESTS="{request_root}"',
        f'-DA5_TEST_PUBLISHED="{published}"', str(source),
        '-framework', 'Foundation', '-o', str(runner)], check=True)
    unsupported = []
    for suffix in ('first', 'second'):
        other = json.loads(json.dumps(body))
        other['vertex']['function'] = 'unsupported_' + suffix
        unsupported.append(enqueue(uid_dir, other))
    output = (work / 'service.log').open('w')
    service = subprocess.Popen([str(runner), '--serve'], stdout=output,
                               stderr=subprocess.STDOUT)
    try:
        status_dir = cache / 'request-status'
        for key in unsupported:
            wait_for(status_dir / f'{key}.json', service, 20)
            status = json.loads((status_dir / f'{key}.json').read_text())
            if status['request_id'] != key or status['status'] != 'unsupported':
                raise AssertionError('unsupported status differs')
        if service.poll() is not None:
            raise AssertionError('worker died while recording multiple statuses')
        request_id = enqueue(uid_dir, body)
        result = published / request_id
        wait_for(result / 'receipt.json', service)
        receipt = json.loads(result.joinpath('receipt.json').read_text())
        if (receipt['request_id'] != request_id or
                receipt['profile_id'] != known['profile_id'] or
                receipt['stage_compiled'] is not True or
                receipt['pipeline_compatible'] is not False):
            raise AssertionError('compiled receipt identity differs')
        for stage in ('vertex', 'fragment'):
            info = receipt[stage]
            binary = result.joinpath(info['file']).read_bytes()
            if len(binary) != info['bytes'] or sha(binary) != info['sha256']:
                raise AssertionError(f'{stage} output differs from receipt')
            pin = known['midgard']['vert' if stage == 'vertex' else 'frag']
            if info['bytes'] != pin['bytes'] or info['sha256'] != pin['sha256']:
                raise AssertionError(f'{stage} does not match pinned native code')
        print(json.dumps({'host_end_to_end': True, 'device_verified': False,
                          'multiple_unsupported_statuses': True,
                          'request_id': request_id, 'receipt': str(result / 'receipt.json'),
                          'vertex_sha256': receipt['vertex']['sha256'],
                          'fragment_sha256': receipt['fragment']['sha256']}, indent=2))
    finally:
        stop(service)
        output.close()
    if a.stale_fragment is not None:
        if known['profile_id'] != 603:
            p.error('--stale-fragment requires profile 603')
        old = a.stale_fragment.read_bytes()
        if (len(old) != 976 or sha(old) !=
                'b7ab26bc9a0da3ff4a5f87e73fe6aaab07680ae383a3fbdd9d8abc000387cd96'):
            raise AssertionError('stale fragment is not the pinned old 603 program')
        old_receipt = json.loads(result.joinpath('receipt.json').read_text())
        old_receipt['fragment'].update(bytes=len(old), sha256=sha(old),
                                       work_registers=6)
        for name in ('receipt.json', 'fragment.midgard'):
            result.joinpath(name).chmod(0o644)
        result.joinpath('fragment.midgard').write_bytes(old)
        result.joinpath('receipt.json').write_bytes(canonical(old_receipt))
        for name in ('receipt.json', 'fragment.midgard'):
            result.joinpath(name).chmod(0o444)
        # A kill immediately after the atomic rename must leave the request
        # name free. The subsequent worker must compile the new recipe while
        # the quarantined old publication remains outside that name.
        with (work / 'stale-interrupt.log').open('w') as log:
            interrupted = subprocess.Popen([str(runner), '--serve'], stdout=log,
                stderr=subprocess.STDOUT,
                env=dict(os.environ, A5_TEST_STOP_AFTER_RENAME603='1'))
            if interrupted.wait(timeout=20) != 57:
                raise AssertionError('stale retirement interruption was not reached')
        if result.exists():
            raise AssertionError('atomic retirement left the request name occupied')
        retired = list(published.glob('.retired603-*'))
        if len(retired) != 1 or sha(retired[0].joinpath('fragment.midgard').read_bytes()) != sha(old):
            raise AssertionError('interrupted retirement lost the old publication')
        with (work / 'stale-upgrade.log').open('w') as log:
            service = subprocess.Popen([str(runner), '--serve'], stdout=log,
                                       stderr=subprocess.STDOUT)
            try:
                for _ in range(120):
                    if service.poll() is not None:
                        raise AssertionError('worker died while upgrading old 603 result')
                    receipt_path = result / 'receipt.json'
                    if receipt_path.exists():
                        now = json.loads(receipt_path.read_text())
                        if now['fragment']['sha256'] == known['midgard']['frag']['sha256']:
                            break
                    time.sleep(1)
                else:
                    raise AssertionError('old 603 publication was not recompiled')
                if ('retired old pixel-UV 603 request=' not in
                        (work / 'stale-interrupt.log').read_text()):
                    raise AssertionError('worker did not explicitly retire old 603 shader')
            finally:
                stop(service)
        assert sha(result.joinpath('fragment.midgard').read_bytes()) == known['midgard']['frag']['sha256']
    # Restart must reuse the existing trusted status directory and keep both
    # unsupported statuses terminal without re-running the compiled request.
    with (work / 'restart.log').open('w') as log:
        service = subprocess.Popen([str(runner), '--serve'], stdout=log,
                                   stderr=subprocess.STDOUT)
        try:
            time.sleep(6)
            if service.poll() is not None or not result.joinpath('receipt.json').is_file():
                raise AssertionError('worker restart did not retain status/cache')
        finally:
            stop(service)
    # Existing symlink, non-directory and wrong-mode objects must fail closed.
    for name in ('symlink', 'file', 'mode'):
        status_dir = cache / 'request-status'
        if status_dir.is_symlink() or status_dir.is_file():
            status_dir.unlink()
        elif status_dir.exists():
            shutil.rmtree(status_dir)
        if name == 'symlink':
            decoy = work / 'status-decoy'
            decoy.mkdir(mode=0o700)
            status_dir.symlink_to(decoy, target_is_directory=True)
        elif name == 'file':
            status_dir.write_text('not a directory')
        else:
            status_dir.mkdir(mode=0o755)
            status_dir.chmod(0o755)
        other = json.loads(json.dumps(body))
        other['vertex']['function'] = 'unsupported_' + name
        enqueue(uid_dir, other)
        with (work / f'reject-{name}.log').open('w') as log:
            service = subprocess.Popen([str(runner), '--serve'], stdout=log,
                                       stderr=subprocess.STDOUT)
            try:
                try:
                    exit_code = service.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    raise AssertionError(f'untrusted {name} status directory accepted')
                if exit_code == 0 or 'untrusted request status directory' not in (
                        work / f'reject-{name}.log').read_text():
                    raise AssertionError(f'untrusted {name} did not fail closed')
            finally:
                if service.poll() is None:
                    stop(service)


if __name__ == '__main__':
    main()
