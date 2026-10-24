#!/usr/bin/env python3
"""Check startup, bounded scan counters and pre-exec filesystem phase logs.

Private temporary metadata fixtures exercise the real service and scanner.
The dispatch case deliberately has no translator executable: no fake shader,
compiler, publication, phone access or GPU submission is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-service-diagnostics-'))
    work.mkdir(parents=True, exist_ok=True)
    if any(work.iterdir()):
        parser.error('work directory must be empty')
    tools, cache, requests, published = (work / name for name in ('tools', 'cache', 'requests', 'published'))
    tools.mkdir()
    cache.mkdir(mode=0o700)
    requests.mkdir(mode=0o1777)
    requests.chmod(0o1777)
    published.mkdir(mode=0o755)
    uid = requests / str(os.geteuid())
    uid.mkdir(mode=0o700)
    (uid / '.lock').touch(mode=0o600)  # provider-created synchronization inode
    library = work / 'metadata-only-library'
    library.write_bytes(b'startup metadata fixture; never compiled')
    source_sha = hashlib.sha256(library.read_bytes()).hexdigest()
    for profile in range(602, 607):
        (tools / f'generic{profile}.json').write_bytes(canonical({
            'profile_id': profile, 'metallib_sha256': source_sha}))
    (tools / 'profile.json').write_bytes(canonical({
        'capabilities': {}, 'profiles': {'test': {'capabilities': []}}}))
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    wrapper = work / 'harness.m'
    wrapper.write_text('''#define main a5OriginalMain
#include "''' + str(source) + '''"
#undef main
int main(int argc,char **argv){
  if(argc>1&&!strcmp(argv[1],"scan")){
    @autoreleasepool { for(unsigned i=0;i<9;i++)a5ScanRequests(@"unused",@[]); }
    return 0;
  }
  if(argc>1&&!strcmp(argv[1],"bounded")){
    @autoreleasepool { for(unsigned i=0;i<300;i++)serviceCheckpoint("bound-test",nil,nil); }
    return 0;
  }
  if(argc>1&&!strcmp(argv[1],"dispatch")){
    @autoreleasepool {
      a5CompileDynamic(NSBundle.mainBundle.executablePath,
        @{@"request_id":@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          @"stage":@"fragment",@"function":@"fragment",@"named_constants":@[],@"indexed_constants":@[]},
        @{@"configured_vertex_packing0":@{},@"vertex_function":@"vertex",@"fragment_function":@"fragment"});
    }
    return 0;
  }
  return a5OriginalMain(argc,argv);
}
''')
    runner = work / 'service-host'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fblocks', '-Os',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations', '-DA5_SHADER_HOST_TEST=1',
        f'-DA5_TEST_TOOLS="{tools}"', f'-DA5_TEST_CACHE="{cache}"',
        f'-DA5_TEST_LIBRARY="{library}"', f'-DA5_TEST_REQUESTS="{requests}"',
        f'-DA5_TEST_PUBLISHED="{published}"', str(wrapper),
        '-framework', 'Foundation', '-o', str(runner)], check=True)
    startup_log = work / 'startup.log'
    with startup_log.open('w') as log:
        process = subprocess.Popen([str(runner), '--serve'], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while 'phase=scan-end ' not in startup_log.read_text():
                assert process.poll() is None, startup_log.read_text()
                assert time.monotonic() < deadline, startup_log.read_text()
                time.sleep(0.01)
        finally:
            process.terminate()
            process.wait(timeout=5)
    startup = startup_log.read_text()
    phases = ['main-roots-begin', 'main-roots-end', 'serve-roots-begin', 'serve-roots-end',
              'stock-read-begin', 'stock-read-end', 'stock-hash-begin', 'stock-hash-end']
    positions = [startup.index('phase=' + phase + ' ') for phase in phases]
    assert positions == sorted(positions), startup
    assert startup.count('phase=recipe-read-begin ') == startup.count('phase=recipe-read-end ') == 5
    for profile in range(602, 607):
        assert f'phase=recipe-read-end pid={process.pid} request=none stage={profile}' in startup

    # Each malformed input reaches a different unchanged validation gate.
    cases = [('1', b'{}', 0o644), ('2', b'[]', 0o600),
             ('3', b'{}', 0o600), ('4', canonical({'request_id': '4' * 64,
                                                'owner_uid': os.geteuid()}), 0o600)]
    for digit, data, mode in cases:
        path = uid / (digit * 64 + '.request.json')
        path.write_bytes(data)
        path.chmod(mode)
    body = {'owner_uid': os.geteuid(), 'kind': 'unknown-metadata'}
    key = hashlib.sha256(canonical(body)).hexdigest()
    path = uid / (key + '.request.json')
    path.write_bytes(canonical(dict(body, request_id=key)))
    path.chmod(0o600)
    scan = subprocess.run([str(runner), 'scan'], capture_output=True, text=True, timeout=10, check=True).stderr
    (work / 'scan.log').write_text(scan)
    summaries = [line for line in scan.splitlines() if ': SCAN scan=' in line]
    assert len(summaries) == 8 and 'SCAN scan=9 ' not in scan, scan
    for index, line in enumerate(summaries):
        # The valid unsupported request is durably retired on the first scan.
        # Unsafe/malformed leaves keep exercising their unchanged rejection gates.
        for field in ('users=1', 'users_rejected=0',
                      'candidates=5' if index == 0 else 'candidates=4',
                      'read_rejected=1', 'json_rejected=1', 'identity_rejected=1',
                      'digest_rejected=1', 'handled=1' if index == 0 else 'handled=0',
                      'capped_users=0'):
            assert field in line, line
    assert scan.count('RETIRED request=' + key) == 1, scan
    assert not path.exists(), 'terminal request must stop consuming the UID quota'
    assert scan.count('UNSUPPORTED request=' + key) == 1, scan
    status = json.loads((cache / 'request-status' / (key + '.json')).read_bytes())
    assert status['status'] == 'unsupported' and not list(published.iterdir())
    bounded = subprocess.run([str(runner), 'bounded'], capture_output=True, text=True, timeout=10, check=True).stderr
    assert bounded.count('SERVICE phase=bound-test ') == 256
    dispatch = subprocess.run([str(runner), 'dispatch'], capture_output=True, text=True, timeout=10)
    (work / 'dispatch.log').write_text(dispatch.stderr)
    assert dispatch.returncode == 1, dispatch.stderr
    phases = ['dispatch', 'workspace-mkdir-begin', 'workspace-mkdir-end',
              'packing-write-sync-begin', 'packing-write-sync-end', 'profile-read-begin',
              'profile-read-end', 'profile-write-sync-begin', 'profile-write-sync-end']
    positions = [dispatch.stderr.index('phase=' + phase + ' ') for phase in phases]
    assert positions == sorted(positions), dispatch.stderr
    assert positions[-1] < dispatch.stderr.index('SPAWN phase=begin'), dispatch.stderr
    assert not list(published.iterdir()), 'missing executable must never publish native code'
    print(json.dumps({'work_dir': str(work), 'startup_order': True, 'scan_summaries': 8,
                      'validation_counters': True, 'service_record_limit': 256,
                      'pre_exec_phase_order': True, 'device_runtime_verified': False}, indent=2))


if __name__ == '__main__':
    main()
