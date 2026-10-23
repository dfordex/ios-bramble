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
    p.add_argument('--dynamic-capture', type=Path,
                   help='new non-profiled fragment constant request to compile without native pins')
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
        # Reuse the same request identity that an older package rejected.
        # Only the newly recognized606 pair may retire this root-private status.
        request_id = sha(canonical(body))
        previous_status = status_dir / f'{request_id}.json'
        failed_key = None
        if known['profile_id'] == 606:
            previous_status.write_bytes(canonical({'schema': 1,
                'request_id': request_id, 'status': 'unsupported',
                'reason': 'previous package has no exact606 recipe'}))
            previous_status.chmod(0o600)
            failed_body = dict(body, descriptor={'host_test_failed_terminal': 1})
            failed_key = sha(canonical(failed_body))
            failed_status = status_dir / f'{failed_key}.json'
            failed_status.write_bytes(canonical({'schema': 1,
                'request_id': failed_key, 'status': 'failed', 'reason': 'terminal failure'}))
            failed_status.chmod(0o600)
            enqueue(uid_dir, failed_body)
        assert enqueue(uid_dir, body) == request_id
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
        if known['profile_id'] == 606:
            if previous_status.exists() or 'RETRY newly supported profile=606' not in (work / 'service.log').read_text():
                raise AssertionError('old unsupported606 status was not safely retired')
            if (published / failed_key).exists() or json.loads(failed_status.read_text())['status'] != 'failed':
                raise AssertionError('terminal failed status was retried')
        print(json.dumps({'host_end_to_end': True, 'device_verified': False,
                          'unsupported606_migration': known['profile_id'] == 606,
                          'multiple_unsupported_statuses': True,
                          'request_id': request_id, 'receipt': str(result / 'receipt.json'),
                          'vertex_sha256': receipt['vertex']['sha256'],
                          'fragment_sha256': receipt['fragment']['sha256']}, indent=2))
    finally:
        stop(service)
        output.close()
    if a.dynamic_capture is not None:
        captured = json.loads(a.dynamic_capture.read_text())
        dynamic_body = dict(function(base, 'fragment', captured), owner_uid=uid)
        dynamic_id = sha(canonical(dynamic_body))
        dynamic_status = cache / 'request-status' / f'{dynamic_id}.json'
        dynamic_status.write_bytes(canonical({'schema': 1, 'request_id': dynamic_id,
            'status': 'unsupported', 'reason': 'previous package cannot compile dynamic stages'}))
        dynamic_status.chmod(0o600)
        enqueue(uid_dir, dynamic_body)
        with (work / 'dynamic.log').open('w') as log:
            service = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
            try:
                dynamic_result = published / dynamic_id
                wait_for(dynamic_result / 'receipt.json', service)
                record = json.loads((dynamic_result / 'receipt.json').read_text())
                assert record['schema'] == 2 and record['kind'] == 'dynamic-stage'
                assert record['stage'] == 'fragment' and record['stage_compiled'] is True
                assert record['pipeline_compatible'] is False and record['request_id'] == dynamic_id
                assert record['function'] == dynamic_body['function']
                assert record['named_constants_sha256'] == sha(canonical(dynamic_body['named_constants']))
                assert record['indexed_constants_sha256'] == sha(canonical(dynamic_body['indexed_constants']))
                assert set(p.name for p in dynamic_result.iterdir()) == {'receipt.json', 'stage.midgard', 'reflection.json'}
                for key in ('native', 'reflection'):
                    meta = record[key]; data = (dynamic_result / meta['file']).read_bytes()
                    assert len(data) == meta['bytes'] and sha(data) == meta['sha256']
                for path in dynamic_result.iterdir():
                    assert path.stat().st_mode & 0o777 == 0o444 and path.stat().st_uid == uid
                assert not dynamic_status.exists()
                known_hashes = {json.loads(path.read_text())['midgard']['frag']['sha256']
                    for path in tools.glob('generic*.json')}
                assert record['native']['sha256'] not in known_hashes, 'dynamic test must compile an unregistered stage'
                reflection = json.loads((dynamic_result / 'reflection.json').read_text())
                assert reflection['compilation_context']['selected_native_stage_only'] is True
                assert record['native_abi']['schema'] == 1
                # The same unpinned path compiles an actual vertex stage;
                # its fragment companion supplies translation scaffolding only.
                vertex_body = dict(base, owner_uid=uid, stage='vertex',
                    function=known['vertex_function'],
                    named_constants=known['vertex_constants'], indexed_constants=[])
                vertex_id = enqueue(uid_dir, vertex_body)
                vertex_path = published / vertex_id / 'receipt.json'
                wait_for(vertex_path, service)
                vertex_record = json.loads(vertex_path.read_text())
                assert vertex_record['schema'] == 2 and vertex_record['stage'] == 'vertex'
                assert vertex_record['stage_compiled'] is True and vertex_record['pipeline_compatible'] is False
                assert vertex_record['native']['bytes'] == 2192
                # Malformed copied bytes and a spoofed library cannot enter
                # the dynamic compiler even if the spool object is owned.
                for bad in ('bytes', 'source'):
                    bad_body = json.loads(json.dumps(dynamic_body))
                    if bad == 'bytes':
                        bad_body['named_constants'][0]['raw'] = 'zz'
                    else:
                        bad_body['metallib_sha256'] = '0' * 64
                    bad_id = enqueue(uid_dir, bad_body)
                    bad_path = cache / 'request-status' / f'{bad_id}.json'
                    wait_for(bad_path, service, 20)
                    assert json.loads(bad_path.read_text())['status'] == 'unsupported'
                    assert not (published / bad_id).exists()
                print(json.dumps({'dynamic_stage_host_end_to_end': True,
                    'request_id': dynamic_id, 'native': record['native'],
                    'receipt': str(dynamic_result / 'receipt.json'),
                    'device_verified': False}, indent=2))
            finally:
                stop(service)
        # Genuine translator errors survive restart and become public terminal
        # failure receipts, so a provider can stop waiting for absent code.
        invalid_body = dict(dynamic_body, function='a5_function_does_not_exist')
        invalid_id = enqueue(uid_dir, invalid_body)
        with (work / 'dynamic-failure.log').open('w') as log:
            service = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
            try:
                if service.wait(timeout=45) == 0:
                    raise AssertionError('nonexistent AIR function unexpectedly compiled')
            finally:
                if service.poll() is None:
                    stop(service)
        failed_record = json.loads((cache / 'request-status' / f'{invalid_id}.json').read_text())
        assert failed_record['status'] == 'failed'
        with (work / 'dynamic-failure-restart.log').open('w') as log:
            service = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
            try:
                failure_path = published / invalid_id / 'receipt.json'
                wait_for(failure_path, service, 20)
                failure = json.loads(failure_path.read_text())
                assert failure['stage_compiled'] is False and failure['pipeline_compatible'] is False
                assert failure['request_id'] == invalid_id and isinstance(failure['error'], str)
                assert set(path.name for path in failure_path.parent.iterdir()) == {'receipt.json'}
                assert json.loads((cache / 'request-status' / f'{invalid_id}.json').read_text()) == failed_record
                if service.poll() is not None:
                    raise AssertionError('failed dynamic stage restarted compilation')
            finally:
                stop(service)
        print('dynamic stage unsupported migration, semantic publication and public terminal failure: PASS')
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
    if known['profile_id'] == 606:
        # A recipe upgrade must not turn status retirement into a symlink,
        # hardlink, mode or identity bypass. All outputs stay private.
        for index, kind in enumerate(('symlink', 'hardlink', 'mode', 'identity')):
            invalid_body = dict(body, descriptor={'host_invalid_status': index})
            invalid_key = sha(canonical(invalid_body))
            invalid_status = cache / 'request-status' / f'{invalid_key}.json'
            decoy = work / f'status-file-decoy-{index}'
            decoy.write_bytes(canonical({'schema': 1, 'request_id': invalid_key,
                'status': 'unsupported', 'reason': 'old unsupported'}))
            decoy.chmod(0o600)
            if kind == 'symlink':
                invalid_status.symlink_to(decoy)
            elif kind == 'hardlink':
                os.link(decoy, invalid_status)
            else:
                shutil.copy2(decoy, invalid_status)
                if kind == 'mode':
                    invalid_status.chmod(0o644)
                else:
                    invalid_status.write_bytes(canonical({'schema': 1,
                        'request_id': '0' * 64, 'status': 'unsupported', 'reason': 'wrong identity'}))
            enqueue(uid_dir, invalid_body)
            with (work / f'reject-status-{kind}.log').open('w') as log:
                service = subprocess.Popen([str(runner), '--serve'], stdout=log,
                                           stderr=subprocess.STDOUT)
                try:
                    code = service.wait(timeout=15)
                    if code == 0 or 'untrusted existing request status' not in (work / f'reject-status-{kind}.log').read_text():
                        raise AssertionError(f'untrusted {kind} status accepted')
                    if (published / invalid_key).exists() or not decoy.exists():
                        raise AssertionError(f'{kind} status rejection changed publication/decoy')
                finally:
                    if service.poll() is None:
                        stop(service)
            invalid_status.unlink()
            (uid_dir / f'{invalid_key}.request.json').unlink()
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
