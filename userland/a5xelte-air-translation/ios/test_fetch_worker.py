#!/usr/bin/env python3
"""Real fetch request -> worker -> native publication and one-time retry tests.

Stock inputs, published bytes, captures and logs stay in the supplied private
work directory. This is host compilation, not a GPU/device success claim.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':')).encode()


def digest(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('translator', 'backend', 'validator', 'known-dir',
                 'metallib', 'capture', 'work-dir'):
        ap.add_argument('--' + name, type=Path, required=True)
    a = ap.parse_args()
    work = a.work_dir.resolve()
    work.mkdir(exist_ok=False)
    tools, spool, cache, published = [work / x for x in ('tools', 'requests', 'cache', 'compiled')]
    for directory, mode in ((tools, 0o755), (spool, 0o1777), (cache, 0o700), (published, 0o755)):
        directory.mkdir(mode=mode)
        directory.chmod(mode)
    for source, name in ((a.translator, 'metal2vulkan'), (a.backend, 'midgard-generic602'),
                         (a.validator, 'spirv-val')):
        shutil.copy2(source, tools / name)
    for path in a.known_dir.glob('*.json'):
        shutil.copy2(path, tools / path.name)
    source = Path(__file__).with_name('a5shader_compile.m')
    runner = work / 'worker'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Os',
        '-DA5_SHADER_HOST_TEST=1', f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{cache}"', f'-DA5_TEST_LIBRARY="{a.metallib}"',
        f'-DA5_TEST_REQUESTS="{spool}"', f'-DA5_TEST_PUBLISHED="{published}"',
        str(source), '-framework', 'Foundation', '-o', str(runner)], check=True)
    uid = os.geteuid()
    user = spool / str(uid)
    user.mkdir(mode=0o700)
    statuses = cache / 'request-status'
    statuses.mkdir(mode=0o700)
    capture = json.loads(a.capture.read_text())
    known = json.loads((tools / 'generic603.json').read_text())
    body = {'schema': 1, 'kind': 'function', 'source_library': 'quartzcore',
        'metallib_sha256': known['metallib_sha256'], 'gpu_id': '07201000',
        'compiler_abi': 1, 'owner_uid': uid, 'stage': 'fragment',
        'function': capture['function'], 'indexed_constants': [],
        'named_constants': [{'name': name, 'type': value['type'],
            'bytes': len(value['raw'])//2, 'raw': value['raw']}
            for name, value in sorted(capture['constants'].items())]}
    def request(b):
        key = digest(b)
        obj = dict(b, request_id=key)
        path = user / f'{key}.request.json'
        path.write_bytes(canonical(obj)); path.chmod(0o600)
        return key, obj
    def old_failure(key, obj, *, archived=False, generation=None):
        reason = 'compiler/validator failed; see /private/var/db/a5shader-cache/.stage-work-previous/air.log'
        receipt = {'schema': 2, 'kind': 'dynamic-stage', 'request_id': key,
            'source_library': 'quartzcore', 'metallib_sha256': obj['metallib_sha256'],
            'gpu_id': '07201000', 'compiler_abi': 1, 'stage': 'fragment',
            'function': obj['function'], 'stage_compiled': False,
            'pipeline_compatible': False,
            'named_constants_sha256': digest(obj['named_constants']),
            'indexed_constants_sha256': digest([]), 'error': reason}
        if generation is not None:
            receipt['support_generation'] = generation
        destination = published / (f'.fetch-old-generation2-{key}' if archived else key)
        destination.mkdir(mode=0o755)
        (destination / 'receipt.json').write_bytes(canonical(receipt))
        (destination / 'receipt.json').chmod(0o444)
        status = statuses / f'{key}.json'
        status.write_bytes(canonical({'schema': 1, 'request_id': key,
            'status': 'failed', 'reason': reason})); status.chmod(0o600)
    key, obj = request(body)
    old_failure(key, obj)
    # A crash after public rename but before private-status rename must resume.
    crash_body = dict(body, indexed_constants=[])
    crash_body['named_constants'] = [dict(x) for x in body['named_constants']]
    # Use a harmless, currently zero, vertex-only specialization to produce a
    # different request identity without changing the requested fragment.
    for item in crash_body['named_constants']:
        if item['name'] == 'fc_vertex_layout':
            item['raw'] = '01'
    crash_key, crash_obj = request(crash_body)
    old_failure(crash_key, crash_obj, archived=True)
    # Current-generation errors must remain terminal even for a fetch request.
    current_body = dict(body, function='a5_current_generation_failure')
    current_key, current_obj = request(current_body)
    old_failure(current_key, current_obj, generation=2)
    current_path = published / current_key / 'receipt.json'
    current_bytes = current_path.read_bytes()
    log = (work / 'service.log').open('w')
    service = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
    try:
        for item in (key, crash_key):
            path = published / item / 'receipt.json'
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if service.poll() is not None:
                    raise AssertionError(f'worker failed: {work / "service.log"}')
                if path.exists() and json.loads(path.read_text()).get('stage_compiled') is True:
                    break
                time.sleep(0.1)
            else:
                raise AssertionError(f'no compiled fetch stage: {path}')
            receipt = json.loads(path.read_text())
            assert receipt['support_generation'] == 2 and receipt['native_abi']['framebuffer_fetch'] is True
            assert 0 < receipt['native']['bytes'] <= 8192
            if item == key:
                assert receipt['native']['bytes'] == 4672
                assert receipt['native_abi']['live_ubos'][-1] == {
                    'native_index': 5, 'min_bytes': 4, 'logical_bytes': 2}
            assert not (statuses / f'{item}.json').exists()
            assert (published / f'.fetch-old-generation2-{item}' / 'receipt.json').exists()
            assert (statuses / f'.fetch-old-generation2-{item}.json').exists()
        assert current_path.read_bytes() == current_bytes
        # Both published successes and the current-generation error are stable
        # across another scan. No repeat translation overwrites their receipts.
        snapshots = {item: (published / item / 'receipt.json').stat().st_mtime_ns
                     for item in (key, crash_key, current_key)}
        time.sleep(6)
        assert service.poll() is None
        assert snapshots == {item: (published / item / 'receipt.json').stat().st_mtime_ns
                             for item in snapshots}
    finally:
        service.terminate()
        try:
            service.wait(timeout=5)
        except subprocess.TimeoutExpired:
            service.kill(); service.wait()
        log.close()
    (work / 'result.json').write_text(json.dumps({'request_id': key,
        'publication': str(published / key), 'spool': str(spool),
        'actual_fetch_publication': True, 'one_time_retry': True,
        'interrupted_retirement_resumed': True,
        'current_generation_failure_stays_terminal': True,
        'device_execution_verified': False}, indent=2)+'\n')
    print((work / 'result.json').read_text())


if __name__ == '__main__':
    main()
