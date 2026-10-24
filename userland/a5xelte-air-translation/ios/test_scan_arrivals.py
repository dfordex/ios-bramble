#!/usr/bin/env python3
"""Compile an authentic function arriving after the scanner's fixed snapshot.

Also exercise62/63/64 archive-pressure boundaries with terminal metadata.
No fake compiler/native output, phone access or GPU submission is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('tools', 'library', 'request', 'reference-publication'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--work-dir', type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-scan-arrivals-'))
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
    actual = json.loads(args.request.read_bytes())
    assert actual['kind'] == 'function' and actual['owner_uid'] == uid
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    harness = work / 'scan.m'
    harness.write_text('''#define A5_SHADER_SCAN_HOST_TEST 1
#define main a5OriginalMain
#include "''' + str(source) + '''"
#undef main
static void arriving(void){
 fprintf(stderr,"TEST after-initial-snapshot\\n");
 NSDictionary *request=readJSON(@"''' + str(args.request.resolve()) + '''");
 NSString *folder=[requestRoot stringByAppendingPathComponent:[@(geteuid())stringValue]];
 writeData(a5Canonical(request),[folder stringByAppendingPathComponent:
  [request[@"request_id"]stringByAppendingString:@".request.json"]]);
 /* Hash-mismatched untrusted late leaf must remain uncompiled/queued. */
 writeData(a5Canonical(request),[folder stringByAppendingPathComponent:
  @"0000000000000000000000000000000000000000000000000000000000000000.request.json"]);
}
static void oldHandler(NSDictionary *request){
 fprintf(stderr,"TEST old-handler request=%s\\n",[request[@"request_id"]UTF8String]);
}
int main(int argc,char **argv){
 if(argc==2&&(!strcmp(argv[1],"scan")||!strcmp(argv[1],"late"))){
  @autoreleasepool {
   NSMutableArray *profiles=[NSMutableArray array];
   for(NSNumber *profile in @[@602,@603,@604,@605,@606])
    [profiles addObject:readJSON([installed stringByAppendingPathComponent:
      [NSString stringWithFormat:@"generic%@.json",profile]])];
   if(!strcmp(argv[1],"late")){a5ScanAfterSnapshot=arriving;a5ScanBeforeOldHandler=oldHandler;}
   a5ScanRequests(NSBundle.mainBundle.executablePath,profiles);
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

    def terminal_rows(count):
        for path in queue.glob('*.request.json'):
            path.unlink()
        for name in ('completed-requests', 'retirement-claims', 'request-status'):
            shutil.rmtree(cache / name, ignore_errors=True)
        statuses = cache / 'request-status'
        statuses.mkdir(mode=0o700)
        for sequence in range(count):
            body = {'owner_uid': uid, 'kind': 'pipeline', 'terminal_sequence': sequence}
            key = hashlib.sha256(canonical(body)).hexdigest()
            path = queue / (key + '.request.json')
            path.write_bytes(canonical(dict(body, request_id=key)))
            path.chmod(0o600)
            path = statuses / (key + '.json')
            path.write_bytes(canonical({'schema': 1, 'request_id': key, 'status': 'unsupported',
                                       'reason': 'terminal scheduling metadata fixture'}))
            path.chmod(0o600)

    terminal_rows(18)
    late = subprocess.run([str(runner), 'late'], capture_output=True, text=True, timeout=90)
    (work / 'late.log').write_text(late.stdout + late.stderr)
    assert late.returncode == 0, late.stderr
    log = late.stderr
    assert log.index('TEST after-initial-snapshot') < log.index('STAGE PUBLISHED stage=') < log.index('TEST old-handler'), log
    assert 'SERVICE phase=arriving-function ' in log and 'candidates=18 ' in log, log
    assert ': RETIRED ' not in log and 'retire-prepare-begin' not in log, log
    assert not (cache / 'completed-requests').exists() and len(list(queue.glob('*.request.json'))) == 20
    assert (published / actual['request_id'] / 'stage.midgard').read_bytes() == (args.reference_publication / 'stage.midgard').read_bytes()
    assert not (published / ('0' * 64)).exists()
    boundaries = {}
    for count in (62, 63, 64):
        terminal_rows(count)
        result = subprocess.run([str(runner), 'scan'], capture_output=True, text=True, timeout=15)
        (work / f'boundary-{count}.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stderr
        retired = result.stderr.count(': RETIRED request=')
        assert retired == int(count >= 63), result.stderr
        assert len(list(queue.glob('*.request.json'))) == count - retired
        if count == 62:
            assert 'retire-prepare-begin' not in result.stderr and not (cache / 'completed-requests').exists()
        boundaries[count] = retired
    proof = {'late_function_dispatched_before_old_handlers': True, 'terminal18_no_archival': True,
             'late_hash_mismatch_not_compiled': True, 'native_matches_genuine_reference': actual['request_id'],
             'archive_attempt_limit': 1, 'retired_at_62_63_64': boundaries, 'device_runtime_verified': False}
    (work / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(dict(proof, work_dir=str(work)), indent=2))


if __name__ == '__main__':
    main()
