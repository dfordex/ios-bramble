#!/usr/bin/env python3
"""Audit actual request read() calls and genuine compilation ahead of38oldnames.

Malformed leaves with forged output/status presence are scheduling fixtures,
never compiler outputs. Native output must match a genuine worker publication.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
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
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-scan-io-'))
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
    assert actual['owner_uid'] == uid and actual['kind'] == 'function'
    fresh_key = actual['request_id']

    def enqueue(key, row):
        path = queue / (key + '.request.json')
        path.write_bytes(canonical(row))
        path.chmod(0o600)
        return path

    def status(key):
        path = statuses / (key + '.json')
        path.write_bytes(canonical({'schema': 1, 'request_id': key, 'status': 'unsupported',
                                   'reason': 'terminal bookkeeping fixture'}))
        path.chmod(0o600)

    old_keys = []
    sequence = 0
    while len(old_keys) < 36:
        body = {'owner_uid': uid, 'kind': 'pipeline', 'terminal_sequence': sequence}
        sequence += 1
        key = hashlib.sha256(canonical(body)).hexdigest()
        if key >= fresh_key:
            continue
        enqueue(key, dict(body, request_id=key))
        status(key)
        old_keys.append(key)
    # Presence may postpone a leaf, but cannot substitute for its body identity.
    malformed_key = '0' * 64
    malformed = enqueue(malformed_key, {'owner_uid': uid, 'request_id': malformed_key, 'kind': 'function'})
    status(malformed_key)
    forged_key = '0' * 63 + '1'
    forged = enqueue(forged_key, actual)
    fake_publication = published / forged_key
    fake_publication.mkdir(mode=0o755)
    receipt = fake_publication / 'receipt.json'
    receipt.write_bytes(b'{}')
    receipt.chmod(0o444)
    original_malformed, original_forged = malformed.read_bytes(), forged.read_bytes()
    enqueue(fresh_key, actual)
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    harness = work / 'scan.m'
    harness.write_text('''#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
static unsigned requestReads,oldReads;
static ssize_t auditRead(int fd,void *bytes,size_t length){
 char path[4096]={0};
 if(length>1&&!fcntl(fd,F_GETPATH,path)&&strstr(path,"/requests/")&&strstr(path,".request.json")){
  const char *name=strrchr(path,'/');name=name?name+1:path;
  if(strstr(name,"''' + fresh_key + '''"))assert(oldReads==0);
  else oldReads++;
  requestReads++;fprintf(stderr,"TEST BODY key=%.64s old=%u\\n",name,oldReads);
 }
 return read(fd,bytes,length);
}
#define read auditRead
#define main a5OriginalMain
#include "''' + str(source) + '''"
#undef main
#undef read
int main(int argc,char **argv){
 if(argc==2&&!strcmp(argv[1],"scan")){
  @autoreleasepool {
   NSMutableArray *profiles=[NSMutableArray array];
   for(NSNumber *profile in @[@602,@603,@604,@605,@606])
    [profiles addObject:readJSON([installed stringByAppendingPathComponent:
      [NSString stringWithFormat:@"generic%@.json",profile]])];
   for(unsigned scan=1;scan<=3;scan++){
    requestReads=oldReads=0;a5ScanRequests(NSBundle.mainBundle.executablePath,profiles);
    fprintf(stderr,"TEST IO scan=%u request_reads=%u old_reads=%u\\n",scan,requestReads,oldReads);
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
    log = result.stderr
    bodies = re.findall(r'TEST BODY key=([a-f0-9]{64}) old=(\d+)', log)
    assert [key for key, _ in bodies] == [fresh_key, malformed_key, forged_key, min(old_keys)], bodies
    counts = re.findall(r'TEST IO scan=(\d+) request_reads=(\d+) old_reads=(\d+)', log)
    assert counts == [('1', '2', '1'), ('2', '1', '1'), ('3', '1', '1')], counts
    assert log.index('STAGE PUBLISHED ') < log.index('TEST BODY key=' + malformed_key), log
    assert (published / fresh_key / 'stage.midgard').read_bytes() == (args.reference_publication / 'stage.midgard').read_bytes()
    assert malformed.read_bytes() == original_malformed and forged.read_bytes() == original_forged
    assert receipt.read_bytes() == b'{}' and not (fake_publication / 'stage.midgard').exists()
    assert 'RETIRED request=' not in log and not (cache / 'completed-requests').exists()
    assert 'digest_rejected=1 ' in log and 'identity_rejected=1 ' in log
    proof = {'old_names': 38, 'first_scan_request_body_reads': 2, 'later_scan_body_reads': 1,
             'fresh_compiled_before_any_old_body_read': True, 'fair_cursor_survives_two_malformed_leaves': True,
             'forged_presence_never_authorizes_code_or_retirement': True,
             'genuine_native_matches_reference': fresh_key, 'device_runtime_verified': False}
    (work / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(dict(proof, work_dir=str(work)), indent=2))


if __name__ == '__main__':
    main()
