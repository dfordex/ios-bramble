#!/usr/bin/env python3
"""Run the real scanner/compiler with64 queued requests and genuine stock tools.

No fake compiler or native output: the pending function is compiled from the
actual captured request and compared with its genuine reference publication.
Old terminal rows and one private failed status are bookkeeping fixtures.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def identify(body):
    return dict(body, request_id=hashlib.sha256(canonical(body)).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('tools', 'library', 'request', 'reference-publication'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--work-dir', type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-scan-priority-'))
    work.mkdir(parents=True, exist_ok=True)
    assert not list(work.iterdir()), 'fresh work directory required'
    cache, spool, published = (work / name for name in ('cache', 'requests', 'published'))
    cache.mkdir(mode=0o700)
    spool.mkdir(mode=0o1777)
    spool.chmod(0o1777)
    published.mkdir(mode=0o755)
    uid = os.geteuid()
    queue = spool / str(uid)
    queue.mkdir(mode=0o700)
    (queue / '.lock').touch(mode=0o600)
    statuses = cache / 'request-status'
    statuses.mkdir(mode=0o700)
    actual = json.loads(args.request.read_bytes())
    assert actual['kind'] == 'function' and actual['owner_uid'] == uid
    key = actual['request_id']
    body = dict(actual)
    body.pop('request_id')
    assert identify(body) == actual

    def enqueue(row):
        path = queue / (row['request_id'] + '.request.json')
        path.write_bytes(canonical(row))
        path.chmod(0o600)
        return path

    def status(row, value):
        path = statuses / (row['request_id'] + '.json')
        path.write_bytes(canonical({'schema': 1, 'request_id': row['request_id'],
            'status': value, 'reason': 'scan scheduling terminal metadata fixture'}))
        path.chmod(0o600)

    # Force old terminal rows to precede the pending genuine request even for
    # a lexicographically ordered directory reader, as on the captured HFS.
    old = []
    sequence = 0
    while len(old) < 62:
        row = identify({'owner_uid': uid, 'kind': 'pipeline', 'test_sequence': sequence})
        sequence += 1
        if row['request_id'] < key:
            old.append(enqueue(row))
            status(row, 'unsupported')
    unsafe = old[0]
    unsafe_bytes = unsafe.read_bytes()
    unsafe.chmod(0o644)
    sequence = 0
    while True:
        failed_body = dict(body, function='scan_priority_previous_failure_' + str(sequence))
        sequence += 1
        failed = identify(failed_body)
        if failed['request_id'] < key:
            break
    enqueue(failed)
    status(failed, 'failed')
    enqueue(actual)
    assert len(list(queue.glob('*.request.json'))) == 64
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    harness = work / 'scan.m'
    harness.write_text('''#define main a5OriginalMain
#include "''' + str(source) + '''"
#undef main
int main(int argc,char **argv){
 if(argc==2&&!strcmp(argv[1],"scan")){
  @autoreleasepool {
   NSMutableArray *profiles=[NSMutableArray array];
   for(NSNumber *profile in @[@602,@603,@604,@605,@606])
    [profiles addObject:readJSON([installed stringByAppendingPathComponent:
      [NSString stringWithFormat:@"generic%@.json",profile]])];
   for(unsigned scan=1;scan<=2;scan++){
    fprintf(stderr,"TEST scan=%u begin\\n",scan);
    a5ScanRequests(NSBundle.mainBundle.executablePath,profiles);
   }
  }
  return 0;
 }
 return a5OriginalMain(argc,argv);
}
''')
    runner = work / 'scan-host'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fblocks', '-Os',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations', '-DA5_SHADER_HOST_TEST=1',
        f'-DA5_TEST_TOOLS="{args.tools.resolve()}"', f'-DA5_TEST_CACHE="{cache}"',
        f'-DA5_TEST_LIBRARY="{args.library.resolve()}"', f'-DA5_TEST_REQUESTS="{spool}"',
        f'-DA5_TEST_PUBLISHED="{published}"', str(harness), '-framework', 'Foundation',
        '-o', str(runner)], check=True)
    result = subprocess.run([str(runner), 'scan'], capture_output=True, text=True, timeout=90)
    (work / 'scan.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    first, second = result.stderr.split('TEST scan=2 begin\n')
    for scan, log in ((1, first), (2, second)):
        assert log.count(': RETIRED request=') == 1, log
        assert unsafe.exists() and unsafe.read_bytes() == unsafe_bytes and unsafe.stat().st_mode & 0o777 == 0o644
        if scan == 1:
            native = published / key / 'stage.midgard'
            assert native.read_bytes() == (args.reference_publication / 'stage.midgard').read_bytes()
            receipt = json.loads((published / key / 'receipt.json').read_bytes())
            assert receipt['request_id'] == key and receipt['stage_compiled'] is True
            complete = log.index('STAGE PUBLISHED stage=')
            retirement = log.index(': RETIRED request=')
            assert complete < retirement, log
            assert 'candidates=64 ' in log and 'maintenance=1 ' in log, log
        else:
            assert 'SPAWN phase=' not in log, log
            assert 'candidates=63 ' in log and 'maintenance=1 ' in log, log
    assert len(list(queue.glob('*.request.json'))) == 62
    assert len(list((cache / 'completed-requests').glob('slot-*.json'))) == 2
    proof = {'queued_candidates': 64, 'pending_function_compiled_before_old_terminal_io': True,
             'genuine_native_matches_reference': key, 'retirement_limit_per_scan': 1,
             'unsafe_leaf_preserved': True, 'second_scan_avoids_recompile': True,
             'device_runtime_verified': False}
    (work / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(dict(proof, work_dir=str(work)), indent=2))


if __name__ == '__main__':
    main()
