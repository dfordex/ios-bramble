#!/usr/bin/env python3
"""Exercise direct tool exec, inherited limits and bounded own-child accounting.

No fake translator/validator, shader source, phone access or publication is used.
A copied actual OS sleep executable runs beyond one 10s reporting interval;
An OS resource probe tests limits/signals/descendants; it emits no shader code.
"""
import argparse
import errno
import json
import os
from pathlib import Path
import re
import shutil
import resource
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-worker-diagnostics-'))
    work.mkdir(exist_ok=True, parents=True)
    if any(work.iterdir()):
        parser.error('work directory must be empty; previous evidence is retained')
    tools = work / 'tools'
    tools.mkdir()
    shutil.copyfile('/bin/sleep', tools / 'sleep')
    (tools / 'sleep').chmod(0o755)
    # Re-sign only the private copied OS tool: its original platform signature
    # is not valid at an untrusted copied path. Executable instructions stay intact.
    subprocess.run(['codesign', '--force', '--sign', '-', str(tools / 'sleep')], check=True)
    invalid = tools / 'invalid-executable'
    invalid.write_bytes(b'Not a Mach-O executable.\x00\x01\x02\x03')
    invalid.chmod(0o755)
    probe_source = work / 'resource-probe.c'
    probe_source.write_text('''#include <sys/resource.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <fcntl.h>
int main(int argc,char **argv){
 struct rlimit limit;if(getrlimit(RLIMIT_FSIZE,&limit))return 90;
 printf("LIMIT soft=%llu hard=%llu pid=%d pgrp=%d request=%s\\n",
  (unsigned long long)limit.rlim_cur,(unsigned long long)limit.rlim_max,getpid(),getpgrp(),getenv("A5_SHADER_DIAG_REQUEST_KEY"));
 fflush(stdout);if(argc<2)return 91;
 if(!strcmp(argv[1],"oversize")){
  static char bytes[1024*1024];int fd=open(argv[2],O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0)return 92;
  for(unsigned i=0;i<9;i++)if(write(fd,bytes,sizeof(bytes))!=(ssize_t)sizeof(bytes))return 93;
  return 94;
 }
 if(!strcmp(argv[1],"memory")){
  size_t size=501ULL*1024*1024;volatile unsigned char *bytes=malloc(size);if(!bytes)return 95;
  for(size_t i=0;i<size;i+=4096)bytes[i]=1;
  sleep(30);free((void*)bytes);return 96;
 }
 if(!strcmp(argv[1],"signal")){raise(SIGTERM);return 97;}
 if(!strcmp(argv[1],"descendant")){
  pid_t child=fork();if(child<0)return 98;if(!child){sleep(30);_exit(0);}
  printf("DESCENDANT pid=%d\\n",child);fflush(stdout);return 0;
 }
 return strcmp(argv[1],"limits")?99:0;
}
''')
    probe = tools / 'resource-probe'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-Os', '-Wall', '-Wextra', '-Werror',
                    str(probe_source), '-o', str(probe)], check=True)
    runner = work / 'worker-host'
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fblocks', '-Os',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
        '-DA5_SHADER_HOST_TEST=1', f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{work / "cache"}"', f'-DA5_TEST_LIBRARY="{work / "unused.metallib"}"',
        str(source), '-framework', 'Foundation', '-o', str(runner)], check=True)
    key = 'ab' * 32
    results = []
    parent_file_limit = resource.getrlimit(resource.RLIMIT_FSIZE)
    for name, tool, arguments, expected in (
            ('actual-os-exec', tools / 'sleep', ['10.25'], 0),
            ('invalid-exec', invalid, [], 1),
            ('inherited-file-limit', probe, ['limits'], 0),
            ('oversize-output', probe, ['oversize', str(work / 'oversize-output')], 1),
            ('oversize-group', probe, ['memory'], 1),
            ('child-signal', probe, ['signal'], 1),
            ('live-descendant', probe, ['descendant'], 1)):
        child_log = work / (name + '-child.log')
        env = dict(os.environ, A5_SHADER_DIAG_REQUEST_KEY='must-be-overridden')
        process = subprocess.Popen([str(runner), '--test-run', key, str(child_log), str(tool), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        stdout, stderr = process.communicate(timeout=25)
        (work / (name + '-parent.log')).write_text(stdout + stderr)
        child = child_log.read_text()
        assert process.returncode == expected, (process.returncode, stderr, child)
        spawned = re.search(r'SPAWN phase=complete parent_pid=(\d+) child_pid=(\d+) pgrp=(\d+) request=([a-f0-9]+) stage=([^ ]+) errno=0', stderr)
        assert 'direct=1 file_limit_bytes=8388608' in stderr
        assert 'WORKER phase=' not in child
        if name == 'invalid-exec':
            assert f'errno={errno.ENOEXEC}' in stderr and 'EXEC_OBSERVED ' not in stderr, stderr
            assert 'FAILED spawn error=' in stderr and not child, (stderr, child)
            results.append({'test': name, 'posix_spawn_errno': errno.ENOEXEC})
            continue
        assert spawned and int(spawned[1]) == process.pid and spawned[2] == spawned[3]
        child_pid = int(spawned[2])
        assert f'request={key}' in stderr and 'must-be-overridden' not in child
        if name == 'actual-os-exec':
            assert 'EXEC_OBSERVED ' in stderr and 'exec_observed=1' in stderr, stderr
            running = next(line for line in stderr.splitlines() if ': RUNNING ' in line)
            for field in ('parent_pid', 'child_pid', 'pgrp', 'request', 'stage', 'exec_observed',
                          'child_accounted', 'child_user_ns', 'child_system_ns', 'child_resident_bytes',
                          'child_footprint_bytes', 'group_user_ns', 'group_system_ns',
                          'group_resident_bytes', 'group_footprint_bytes', 'log_bytes'):
                assert field + '=' in running, running
            assert re.search(r'child_accounted=1 ', running), running
            assert 'log_bytes=0' in running, running
            assert re.search(r': EXIT .*exited=1 exit_code=0 signal=0 exec_observed=1', stderr), stderr
            assert 'exec-failed' not in child
        else:
            assert f'LIMIT soft=8388608 hard=8388608 pid={child_pid} pgrp={child_pid} request={key}' in child, child
            if name == 'oversize-output':
                assert (work / 'oversize-output').stat().st_size == 8 * 1024 * 1024
                assert f'signal={signal.SIGXFSZ}' in stderr, stderr
            elif name == 'oversize-group':
                assert 'compiler group exceeded500MiB' in stderr, stderr
            elif name == 'child-signal':
                assert f'signal={signal.SIGTERM}' in stderr, stderr
            elif name == 'live-descendant':
                assert 'DESCENDANT pid=' in child and 'compiler left live descendants or accounting failed' in stderr, (stderr, child)
        results.append({'test': name, 'parent_pid': process.pid, 'child_pid': child_pid,
            'direct_child_verified': True, 'exit_status': process.returncode,
            'actual_exec_observed': 'EXEC_OBSERVED ' in stderr, 'device_runtime_verified': False})
    assert resource.getrlimit(resource.RLIMIT_FSIZE) == parent_file_limit
    rejected_log = work / 'untrusted-path-child.log'
    rejected = subprocess.run([str(runner), '--test-run', key, str(rejected_log), '/bin/sleep', '.1'],
                              capture_output=True, text=True, timeout=5)
    assert rejected.returncode == 1 and 'compiler executable path rejected' in rejected.stderr
    assert 'SPAWN phase=' not in rejected.stderr and not rejected_log.exists()
    results.append({'test': 'untrusted-tool-path', 'rejected_before_spawn': True})
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps({'work_dir': str(work), 'tests': results}, indent=2))


if __name__ == '__main__':
    main()
