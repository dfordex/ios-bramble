#!/usr/bin/env python3
"""Exercise real worker exec, bounded own-child accounting, and errno failures.

No fake translator/validator, shader source, phone access or publication is used.
A copied actual OS sleep executable runs beyond one 10s reporting interval;
an executable-mode malformed file exercises the real execv ENOEXEC path.
"""
import argparse
import errno
import json
import os
from pathlib import Path
import re
import shutil
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
    runner = work / 'worker-host'
    source = Path(__file__).with_name('a5shader_compile.m').resolve()
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fblocks', '-Os',
        '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
        '-DA5_SHADER_HOST_TEST=1', f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{work / "cache"}"', f'-DA5_TEST_LIBRARY="{work / "unused.metallib"}"',
        str(source), '-framework', 'Foundation', '-o', str(runner)], check=True)
    key = 'ab' * 32
    results = []
    for name, tool, arguments, expected in (
            ('actual-os-exec', tools / 'sleep', ['10.25'], 0),
            ('invalid-exec', invalid, [], 1)):
        child_log = work / (name + '-child.log')
        env = dict(os.environ, A5_SHADER_DIAG_REQUEST_KEY='must-be-overridden')
        process = subprocess.Popen([str(runner), '--test-run', key, str(child_log), str(tool), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        stdout, stderr = process.communicate(timeout=25)
        (work / (name + '-parent.log')).write_text(stdout + stderr)
        child = child_log.read_text()
        assert process.returncode == expected, (process.returncode, stderr, child)
        spawned = re.search(r'SPAWN phase=complete parent_pid=(\d+) child_pid=(\d+) pgrp=(\d+) request=([a-f0-9]+) stage=([^ ]+) errno=0', stderr)
        assert spawned and int(spawned[1]) == process.pid and spawned[2] == spawned[3]
        child_pid = int(spawned[2])
        for phase in ('main-entry', 'limits-ready', 'exec-attempt'):
            assert re.search(rf'WORKER phase={phase} parent_pid={process.pid} child_pid={child_pid} pgrp={child_pid} request={key} stage=', child), child
        assert f'request={key}' in stderr and 'must-be-overridden' not in child
        if expected == 0:
            assert 'EXEC_OBSERVED ' in stderr and 'exec_observed=1' in stderr, stderr
            running = next(line for line in stderr.splitlines() if ': RUNNING ' in line)
            for field in ('parent_pid', 'child_pid', 'pgrp', 'request', 'stage', 'exec_observed',
                          'child_accounted', 'child_user_ns', 'child_system_ns', 'child_resident_bytes',
                          'child_footprint_bytes', 'group_user_ns', 'group_system_ns',
                          'group_resident_bytes', 'group_footprint_bytes', 'log_bytes'):
                assert field + '=' in running, running
            assert re.search(r'child_accounted=1 ', running), running
            assert re.search(r'log_bytes=[1-9][0-9]*', running), running
            assert re.search(r': EXIT .*exited=1 exit_code=0 signal=0 exec_observed=1', stderr), stderr
            assert 'exec-failed' not in child
        else:
            assert f'phase=exec-failed ' in child and f'errno={errno.ENOEXEC}' in child, child
            assert re.search(r': EXIT .*exited=1 exit_code=126 signal=0 exec_observed=0', stderr), stderr
            assert 'EXEC_OBSERVED ' not in stderr
        results.append({'test': name, 'parent_pid': process.pid, 'child_pid': child_pid,
            'worker_context_verified': True, 'exit_status': process.returncode,
            'actual_exec_observed': expected == 0, 'device_runtime_verified': False})
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps({'work_dir': str(work), 'tests': results}, indent=2))


if __name__ == '__main__':
    main()
