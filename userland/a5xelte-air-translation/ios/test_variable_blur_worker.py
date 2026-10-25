#!/usr/bin/env python3
"""Real stock variable-blur pair -> AIR -> native stage publications.

Also exercises original status-only failure migration, old typed failure
migration, and the rule that current-generation failures stay terminal. All
stock/request/native artifacts remain in a fresh private output directory.
This does not claim that a device submitted or rendered the shader.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':')).encode()


def digest(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ('tools', 'stock', 'request', 'output'):
        ap.add_argument('--' + arg, type=Path, required=True)
    a = ap.parse_args()
    work = a.output.resolve()
    work.mkdir(mode=0o700, exist_ok=False)
    spool, cache, published = [work / x for x in ('requests', 'cache', 'compiled')]
    for directory, mode in ((spool, 0o1777), (cache, 0o700), (published, 0o755)):
        directory.mkdir(mode=mode)
        directory.chmod(mode)
    uid = os.geteuid()
    owner = spool / str(uid)
    owner.mkdir(mode=0o700)
    statuses = cache / 'request-status'
    statuses.mkdir(mode=0o700)
    original = json.loads(a.request.read_text())
    assert original['function'] == 'variable_blur_downsample_frag_lph'
    assert original['named_constants'] == original['indexed_constants'] == []
    original.pop('request_id')
    original['owner_uid'] = uid
    reason = 'compiler/validator failed; see /private/var/db/a5shader-cache/.stage-work-old/air.log'

    def request(body):
        key = digest(body)
        obj = dict(body, request_id=key)
        path = owner / (key + '.request.json')
        path.write_bytes(canonical(obj)); path.chmod(0o600)
        return key, obj

    def old_failure(key, obj, generation=None, archived=False):
        status = statuses / (key + '.json')
        status.write_bytes(canonical({'schema': 1, 'request_id': key,
            'status': 'failed', 'reason': reason})); status.chmod(0o600)
        if generation is None:
            return
        receipt = {'schema': 2, 'kind': 'dynamic-stage', 'request_id': key,
            'source_library': 'quartzcore', 'metallib_sha256': obj['metallib_sha256'],
            'gpu_id': '07201000', 'compiler_abi': 1, 'stage': obj['stage'],
            'function': obj['function'], 'stage_compiled': False,
            'pipeline_compatible': False, 'support_generation': generation,
            'named_constants_sha256': digest(obj['named_constants']),
            'indexed_constants_sha256': digest(obj['indexed_constants']), 'error': reason}
        if 'blend_state' in obj:
            receipt['blend_state'] = obj['blend_state']
        destination = published / (('.variable-blur-old-generation3-' + key) if archived else key)
        destination.mkdir(mode=0o755)
        (destination / 'receipt.json').write_bytes(canonical(receipt))
        (destination / 'receipt.json').chmod(0o444)

    fragment_key, fragment = request(original)
    old_failure(fragment_key, fragment)  # Exact 0234 status-only shape.
    vertex_key, vertex = request(dict(original, stage='vertex', function='variable_blur_vert_lph'))
    old_failure(vertex_key, vertex, 2)
    current_body = dict(original, blend_state={'format': 80, 'write_mask': 0,
        'rgb_operation': 0, 'alpha_operation': 0, 'source_rgb': 1,
        'destination_rgb': 0, 'source_alpha': 1, 'destination_alpha': 0})
    interrupted_body = dict(current_body, blend_state=dict(current_body['blend_state'], write_mask=15))
    interrupted_key, interrupted = request(interrupted_body)
    old_failure(interrupted_key, interrupted, 2, archived=True)
    current_key, current = request(current_body)
    old_failure(current_key, current, 3)
    current_path = published / current_key / 'receipt.json'
    current_bytes = current_path.read_bytes()
    runner = work / 'worker'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Os',
        '-Wall', '-Wextra', '-Werror', '-DA5_SHADER_HOST_TEST=1',
        f'-DA5_TEST_TOOLS="{a.tools.resolve()}"',
        f'-DA5_TEST_LIBRARY="{a.stock.resolve()}"', f'-DA5_TEST_CACHE="{cache}"',
        f'-DA5_TEST_REQUESTS="{spool}"', f'-DA5_TEST_PUBLISHED="{published}"',
        str(Path(__file__).with_name('a5shader_compile.m')),
        '-framework', 'Foundation', '-o', str(runner)], check=True)
    log = (work / 'worker.log').open('w')
    service = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
    results = []
    try:
        for key, obj in ((fragment_key, fragment), (vertex_key, vertex), (interrupted_key, interrupted)):
            path = published / key / 'receipt.json'
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if service.poll() is not None:
                    raise AssertionError(f'worker failed; see {work / "worker.log"}')
                if path.exists() and json.loads(path.read_text()).get('stage_compiled') is True:
                    break
                time.sleep(0.1)
            else:
                raise AssertionError(f'no compiled blur stage: {path}')
            receipt = json.loads(path.read_text())
            assert receipt['support_generation'] == 3
            assert receipt['function'] == obj['function'] and receipt['stage'] == obj['stage']
            assert receipt['pipeline_compatible'] is False  # Native pipeline factory is separate.
            code = (path.parent / receipt['native']['file']).read_bytes()
            assert len(code) == receipt['native']['bytes'] and len(code) > 0
            assert hashlib.sha256(code).hexdigest() == receipt['native']['sha256']
            reflection = json.loads((path.parent / 'reflection.json').read_text())
            context = reflection['compilation_context']
            assert context['companion_function'] == (
                'variable_blur_vert_lph' if obj['stage'] == 'fragment'
                else 'variable_blur_downsample_frag_lph')
            assert context['translation_named_constants'] == []
            assert context['translation_indexed_constants'] == []
            assert (published / ('.variable-blur-old-generation3-' + key) / 'receipt.json').exists()
            assert (statuses / ('.variable-blur-old-generation3-' + key + '.json')).exists()
            assert not (statuses / (key + '.json')).exists()
            if obj['stage'] == 'vertex':
                assert [v['components'] for v in receipt['native_abi']['inputs']] == [4, 2, 2]
                assert [v['components'] for v in receipt['native_abi']['outputs']] == [4, 1, 2, 2]
            else:
                bindings = reflection['layout']['sets'][0]['bindings']
                sampler = next(b['immutable_sampler'] for b in bindings if b['ty'] == 1)
                assert sampler['min_filter'] == sampler['mag_filter'] == 1
                assert sampler['address_mode_u'] == sampler['address_mode_v'] == 3
                assert sampler['border_color'] == 0 and sampler['max_lod'] == 15
            results.append({'stage': obj['stage'], 'native_bytes': len(code),
                'native_abi': receipt['native_abi']})
        assert current_path.read_bytes() == current_bytes
        snapshots = {k: (published / k / 'receipt.json').stat().st_mtime_ns
                     for k in (fragment_key, vertex_key, interrupted_key, current_key)}
        time.sleep(6)
        assert service.poll() is None
        assert snapshots == {k: (published / k / 'receipt.json').stat().st_mtime_ns
                             for k in snapshots}
    finally:
        service.terminate()
        try:
            service.wait(timeout=5)
        except subprocess.TimeoutExpired:
            service.kill(); service.wait()
        log.close()
    proof = {'real_air_and_native_stages': results, 'legacy_status_only_retry': True,
        'typed_old_generation_retry': True, 'interrupted_retirement_resumed': True,
        'current_generation_failure_preserved': True,
        'publications_stable_across_scan': True, 'physical_gpu_execution': False}
    (work / 'result.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(proof, indent=2))


if __name__ == '__main__':
    main()
