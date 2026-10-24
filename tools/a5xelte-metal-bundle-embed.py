#!/usr/bin/env python3
"""Embed this project's signed Metal bundle in a private XNU include.

The output belongs in bsd/kern/A5XELTEMetalBundlePayload.inc of the local
XNU build tree. It is a generated binary artifact and must not be committed.
No device access or filesystem image modification is performed here.
"""
from __future__ import annotations

import argparse
import collections
import copy
import ctypes
import os
import stat
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import zlib


BUNDLE_DEST = "/System/Library/Extensions/A5MaliMetal.bundle"
PROBE_DEST = "/usr/libexec/a5mali-metal-probe"
PLIST_DEST = "/System/Library/LaunchDaemons/com.orhunnx.a5mali-metal-probe.plist"
CACHE_DEST = "/System/Library/xpc/launchd.plist"
MAX_FILE = 2 * 1024 * 1024
MAX_TOTAL = 4 * 1024 * 1024
DISPLAY_APPS = ('ClockAngel.app', 'InputUI.app', 'MediaRemoteUI.app',
                'PaperBoard.app', 'PosterBoard.app', 'PreBoard.app')
MAX_APP_FILE = 32 * 1024 * 1024
MAX_ENTRIES = 4096


def c_string(value: str) -> str:
    # Escape actual UTF-8 bytes, avoiding C universal-character/surrogate issues.
    return '"' + ''.join(chr(b) if 32 <= b < 127 and b not in (34, 92)
                         else '\\' + format(b, '03o') for b in value.encode('utf-8')) + '"'


def xattr_names(path: Path) -> list[str]:
    if hasattr(os, 'listxattr'):
        return os.listxattr(path, follow_symlinks=False)
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    fn = lib.listxattr
    fn.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    fn.restype = ctypes.c_ssize_t
    n = fn(os.fsencode(path), None, 0, 1)  # XATTR_NOFOLLOW
    if n < 0:
        raise OSError(ctypes.get_errno(), 'listxattr', str(path))
    if not n:
        return []
    buf = ctypes.create_string_buffer(n)
    size = fn(os.fsencode(path), buf, n, 1)
    if size < 0:
        raise OSError(ctypes.get_errno(), 'listxattr', str(path))
    return [x.decode('utf-8') for x in buf.raw[:size].split(b'\0') if x]


def display_app_entries(source: Path):
    """Exact six bundles; no following links or silently dropping functional xattrs."""
    files, directories = [], []
    attrs, omitted = collections.Counter(), collections.Counter()
    storage_attrs = {'com.apple.decmpfs', 'com.apple.provenance', 'com.apple.quarantine',
                     'com.apple.metadata:kMDItemWhereFroms'}

    def visit(path: Path, logical: str, descend: bool = True):
        st = path.lstat()
        if not (stat.S_ISDIR(st.st_mode) or stat.S_ISREG(st.st_mode)):
            raise ValueError(f'display apps require regular files/directories, no links: {path}')
        if len(logical.encode('utf-8')) >= 1024 or '\0' in logical or any(
                x in ('', '.', '..') for x in logical.split('/')[1:]):
            raise ValueError(f'noncanonical display-app path: {logical!r}')
        if st.st_uid > 0xffffffff or st.st_gid > 0xffffffff:
            raise ValueError(f'uid/gid outside uint32: {path}')
        for name in xattr_names(path):
            attrs[name] += 1
            if name not in storage_attrs:
                raise ValueError(f'functional/unknown xattr not representable: {path}: {name}')
            omitted[name] += 1
        mode = stat.S_IMODE(st.st_mode)
        if stat.S_ISDIR(st.st_mode):
            directories.append((logical, mode, st.st_uid, st.st_gid))
            if descend:
                for child in sorted(path.iterdir(), key=lambda x: x.name.encode('utf-8')):
                    visit(child, logical + '/' + child.name)
        else:
            if st.st_size > MAX_APP_FILE:
                raise ValueError(f'app file exceeds32MiB: {path}')
            fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
            with os.fdopen(fd, 'rb') as stream:
                before = os.fstat(stream.fileno())
                data = stream.read(MAX_APP_FILE + 1)
                after = os.fstat(stream.fileno())
            def identity(s):
                return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode, s.st_uid, s.st_gid)
            if identity(st) != identity(before) or identity(before) != identity(after) or len(data) != st.st_size:
                raise ValueError(f'app source changed while reading: {path}')
            files.append((logical, data, mode, st.st_uid, st.st_gid))
        if len(files) + len(directories) > MAX_ENTRIES:
            raise ValueError('display app record count exceeds4096')

    if source.is_symlink() or not source.is_dir():
        raise ValueError('display-apps must name a real Applications directory')
    visit(source, '/Applications', False)
    for name in DISPLAY_APPS:
        app = source / name
        if app.is_symlink() or not app.is_dir():
            raise ValueError(f'missing/linked required display bundle: {app}')
        visit(app, '/Applications/' + name)
    directories.sort(key=lambda e: e[0].encode('utf-8'))
    files.sort(key=lambda e: e[0].encode('utf-8'))
    return files, directories, {'observed': dict(attrs), 'omittedStorageOrProvenance': dict(omitted),
                              'functionalXattrsOmitted': False}


COMPILER_PLIST_DEST = '/System/Library/LaunchDaemons/com.orhunnx.a5shader-compile.plist'
BACKBOARD_PLIST_DEST = '/System/Library/LaunchDaemons/com.apple.backboardd.plist'


def backboard_ignore_mach_send_errors(cache: dict) -> dict:
    """Exact QuartzCore option, scoped to the existing backboardd launch job.

    This does not turn a failed Metal pipeline into an executable pipeline.
    Keep every other cache object and job property intact.
    """
    result = copy.deepcopy(cache)
    jobs = result.get('LaunchDaemons') if isinstance(result, dict) else None
    job = jobs.get(BACKBOARD_PLIST_DEST) if isinstance(jobs, dict) else None
    if (not isinstance(job, dict) or job.get('Label') != 'com.apple.backboardd' or
            job.get('ProgramArguments') != ['/usr/libexec/backboardd']):
        raise ValueError('exact existing backboardd launch job required')
    env = job.get('EnvironmentVariables', {})
    if not isinstance(env, dict) or not all(isinstance(k, str) and isinstance(v, str)
                                           for k, v in env.items()):
        raise ValueError('backboardd environment must be a string dictionary')
    env = dict(env)
    env['CA_IGNORE_MACH_SEND_ERRORS'] = '1'
    job['EnvironmentVariables'] = env
    return result


def regular_bytes(path: Path, maximum: int = MAX_FILE) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"regular file required: {path}")
    if not 0 < path.stat().st_size <= maximum:
        raise ValueError(f"file size outside 1..{maximum}: {path}")
    return path.read_bytes()


def arm64_macho(data: bytes, name: str) -> None:
    if len(data) < 32 or struct.unpack_from("<II", data) != (0xFEEDFACF, 0x0100000C):
        raise ValueError(f"thin arm64 Mach-O required: {name}")


COMPILED_ROOT = '/private/var/tmp/a5mali-shader-compiled'
COMPILED_MEMBERS = ('receipt.json', 'reflection.json', 'stage.midgard')
SOURCE_LIBRARY_SHA = '11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9'


def compiled_stage_entries(publication: Path, request_path: Path, validation_out: Path):
    """Authenticate an exact typed request with the production cache reader.

    The host source keeps its current UID and read-only publication modes; the
    boot payload explicitly installs root:wheel ownership. Native ABI derivation
    is shared with the real provider, never a relaxed packaging interpretation.
    """
    import hashlib
    import re
    def sha(data):
        return hashlib.sha256(data).hexdigest()
    def canonical(value):
        return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate compiled-stage JSON key')
            result[key] = value
        return result
    def decode(data):
        return json.loads(data, object_pairs_hook=unique)
    if publication.is_symlink():
        raise ValueError("compiled-stage leaf must not be a symlink")
    # Resolve trusted caller path aliases once, then open only the canonical
    # directory chain and no-follow publication leaves.
    publication = publication.resolve(strict=True)
    if not re.fullmatch('[a-f0-9]{64}', publication.name):
        raise ValueError('compiled-stage directory must be its canonical request identity')
    for parent in (publication, *publication.parents):
        st = parent.lstat()
        if not stat.S_ISDIR(st.st_mode):
            raise ValueError('compiled-stage source ancestors must be real directories')
    root_stat = publication.parent.stat()
    if set(p.name for p in publication.iterdir()) != set(COMPILED_MEMBERS):
        raise ValueError('compiled-stage must contain exactly three fixed publication files')
    contents = {}
    for name in COMPILED_MEMBERS:
        path = publication / name
        st = path.lstat()
        maximum = 8192 if name == 'stage.midgard' else 256*1024 if name == 'reflection.json' else 128*1024
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_dev != root_stat.st_dev:
            raise ValueError('compiled-stage source must be same-filesystem single-link regular files')
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as stream:
            before = os.fstat(stream.fileno())
            data = stream.read(maximum+1)
            after = os.fstat(stream.fileno())
        def identity(v):
            return (v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns,v.st_mode,v.st_uid,v.st_gid,v.st_nlink)
        if identity(st) != identity(before) or identity(before) != identity(after) or not 0 < len(data) <= maximum or len(data) != st.st_size:
            raise ValueError('compiled-stage source changed or exceeds bounds')
        contents[name] = data
    request = decode(regular_bytes(request_path,128*1024))
    if not isinstance(request,dict) or set(request) != {'schema','kind','source_library','metallib_sha256','gpu_id','compiler_abi','stage','function','named_constants','indexed_constants','owner_uid','request_id'}:
        raise ValueError('compiled-stage requires exact canonical function request')
    body = dict(request)
    key = body.pop('request_id')
    if key != publication.name or sha(canonical(body)) != key or type(body['owner_uid']) is not int or not 0 <= body['owner_uid'] <= 0xffffffff:
        raise ValueError('compiled-stage canonical request identity mismatch')
    receipt = decode(contents['receipt.json'])
    if (receipt.get('schema') != 2 or receipt.get('kind') != 'dynamic-stage' or
        receipt.get('request_id') != key or receipt.get('source_library') != 'quartzcore' or
        receipt.get('metallib_sha256') != SOURCE_LIBRARY_SHA or receipt.get('gpu_id') != '07201000' or
        receipt.get('compiler_abi') != 1 or receipt.get('stage') not in ('vertex','fragment') or
        receipt.get('stage') != body['stage'] or receipt.get('function') != body['function'] or
        receipt.get('stage_compiled') is not True or receipt.get('pipeline_compatible') is not False or
        receipt.get('support_generation') != 2 or
        receipt.get('named_constants_sha256') != sha(canonical(body['named_constants'])) or
        receipt.get('indexed_constants_sha256') != sha(canonical(body['indexed_constants']))):
        raise ValueError('compiled-stage receipt source/stage/ABI/request identity mismatch')
    native, reflection = receipt['native'], receipt['reflection']
    for metadata, name in ((native,'stage.midgard'), (reflection,'reflection.json')):
        if metadata.get('file') != name or metadata.get('bytes') != len(contents[name]) or metadata.get('sha256') != sha(contents[name]):
            raise ValueError('compiled-stage publication hash/size mismatch')
    code = contents['stage.midgard']
    if (len(code)&15 or not 1 <= native.get('work_registers',0) <= 16 or
        native.get('tls_bytes') != 0 or native.get('wls_bytes') != 0 or
        native.get('first_tag') not in (2,3,4,5,8,9,10,11,12,13,14,15) or
        code[0]&15 != native['first_tag']):
        raise ValueError('compiled-stage native bounds or header mismatch')
    # The real loader checks typed constants, source pins, canonical current UID,
    # native IO/UBO/texture windows, sampling/packing, and every reflected ABI.
    source = Path(__file__).resolve().parents[1] / 'userland/a5mali-metal'
    validation_out.mkdir(parents=True,exist_ok=True)
    suffix = sha(os.fsencode(publication.parent))[:16]
    check = validation_out / ('cache-check-'+suffix+'.m')
    binary = validation_out / ('cache-check-'+suffix)
    check.write_text('''#import "A5MaliDynamicShaderCache.h"
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=3)return 2;
 NSData*d=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
 NSMutableDictionary*p=[[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]mutableCopy];
 [p removeObjectForKey:@"owner_uid"];[p removeObjectForKey:@"request_id"];
 NSError*e=nil;id entry=A5MaliLoadDynamicShaderStage([NSString stringWithUTF8String:argv[2]],p,&e);
 if(!entry){fprintf(stderr,"actual provider cache rejected stage: %s\\n",e.localizedDescription.UTF8String);return 1;}
 puts("PASS actual provider cache identity and reflected ABI");return 0;}}
''')
    subprocess.run(['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
        '-DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1',f'-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="{publication.parent}"',
        '-I'+str(source),str(source/'A5MaliDynamicShaderCache.m'),str(check),
        '-framework','Foundation','-framework','Metal','-o',str(binary)],check=True)
    subprocess.run([str(binary),str(request_path.resolve()),key],check=True)
    destination = COMPILED_ROOT + '/' + key
    return ([(destination+'/'+name,contents[name],0o444,0,0) for name in COMPILED_MEMBERS],
            [(COMPILED_ROOT,0o755,0,0),(destination,0o755,0,0)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--probe", type=Path)
    parser.add_argument("--launch-plist", type=Path)
    parser.add_argument("--launchd-cache", type=Path,
                        help="current device launchd cache; only add the probe job")
    parser.add_argument('--compiler-dir', type=Path,
                        help='private native compiler package; requires compressed installer patch0172')
    parser.add_argument('--installer-source',type=Path,
                        help='actual staged kernel installer; required for automatic compiler payload preflight')
    parser.add_argument('--compiled-stage',type=Path,action='append',default=[],
                        help='exact three-file dynamic-stage publication; repeat with matching --compiled-request')
    parser.add_argument('--compiled-request',type=Path,action='append',default=[],
                        help='exact canonical function request for each --compiled-stage, in the same order')
    parser.add_argument('--display-apps', type=Path,
                        help='mounted source Applications; embeds only six fixed display bundles, requires installer support')
    parser.add_argument('--backboard-ignore-mach-send-errors', action='store_true',
                        help='set verified QuartzCore Mach-send option only in the existing backboardd cached job')
    args = parser.parse_args()
    if len(args.compiled_stage)!=len(args.compiled_request) or len(args.compiled_stage)>32:
        parser.error('each compiled stage needs one exact request; maximum32')
    if args.compiled_stage and not args.installer_source:
        parser.error('compiled-stage installation requires actual --installer-source preflight')
    if bool(args.probe) != bool(args.launch_plist):
        parser.error("--probe and --launch-plist must be provided together")
    if args.backboard_ignore_mach_send_errors and not (args.probe and args.launchd_cache):
        parser.error('--backboard-ignore-mach-send-errors requires probe and launchd cache')
    if args.launchd_cache and not args.launch_plist:
        parser.error("--launchd-cache requires --probe and --launch-plist")
    if args.compiler_dir and not args.launchd_cache:
        parser.error('--compiler-dir requires --launchd-cache')
    if args.bundle.is_symlink() or not args.bundle.is_dir():
        parser.error("bundle must be a regular directory")
    required = {"A5MaliMetal", "Info.plist", "_CodeSignature/CodeResources"}
    actual = {str(p.relative_to(args.bundle)) for p in args.bundle.rglob("*") if not p.is_dir()}
    if actual != required:
        parser.error(f"unexpected bundle members: {sorted(actual ^ required)}")
    entries: list[tuple[str, bytes, int]] = []
    for name in sorted(required):
        data = regular_bytes(args.bundle / name)
        if name == "A5MaliMetal":
            arm64_macho(data, name)
        elif name == "Info.plist":
            info = plistlib.loads(data)
            if info.get("CFBundleExecutable") != "A5MaliMetal" or info.get("NSPrincipalClass") != "A5MaliMetalDevice":
                parser.error("bundle executable/principal class differs from A5MaliMetal")
        entries.append((f"{BUNDLE_DEST}/{name}", data, 0o755 if name == "A5MaliMetal" else 0o644))
    if args.probe:
        probe = regular_bytes(args.probe)
        arm64_macho(probe, str(args.probe))
        launch = regular_bytes(args.launch_plist)
        plist = plistlib.loads(launch)
        if plist.get("ProgramArguments", [None])[0] != PROBE_DEST:
            parser.error(f"launch job must execute {PROBE_DEST}")
        entries.extend(((PROBE_DEST, probe, 0o755), (PLIST_DEST, launch, 0o644)))
        if args.launchd_cache:
            cache = plistlib.loads(regular_bytes(args.launchd_cache))
            if args.backboard_ignore_mach_send_errors:
                cache = backboard_ignore_mach_send_errors(cache)
            jobs = cache.get("LaunchDaemons") if isinstance(cache, dict) else None
            if not isinstance(jobs, dict):
                parser.error("launchd cache must contain a LaunchDaemons dictionary")
            # Preserve every original object, adding exactly this signed probe job.
            if PLIST_DEST in jobs and jobs[PLIST_DEST] != plist:
                parser.error("cache already contains a different probe job")
            jobs[PLIST_DEST] = plist
            if args.compiler_dir:
                compiler_launch = regular_bytes(args.compiler_dir / 'compiler-launchdaemon.plist')
                compiler_plist = plistlib.loads(compiler_launch)
                if compiler_plist.get('ProgramArguments') not in (['/usr/libexec/a5shader-compile','--selftest'],['/usr/libexec/a5shader-compile','--serve']):
                    parser.error('unexpected compiler launch arguments')
                if COMPILER_PLIST_DEST in jobs and jobs[COMPILER_PLIST_DEST] != compiler_plist:
                    previous = dict(compiler_plist)
                    previous['ProgramArguments'] = ['/usr/libexec/a5shader-compile','--selftest']
                    previous.pop('KeepAlive', None)
                    if jobs[COMPILER_PLIST_DEST] != previous:
                        parser.error('cache contains an unrecognized different compiler job')
                jobs[COMPILER_PLIST_DEST] = compiler_plist
            patched_cache = plistlib.dumps(cache, fmt=plistlib.FMT_BINARY, sort_keys=False)
            if len(patched_cache) > MAX_FILE:
                parser.error("patched launchd cache exceeds 2 MiB bound")
            entries.append((CACHE_DEST, patched_cache, 0o644))
    if args.compiler_dir:
        compiler_members = {
            'a5shader-compile','a5shader/metal2vulkan','a5shader/midgard-compile',
            'a5shader/spirv-val','a5shader/profile.json','a5shader/pairs.json',
            'compiler-launchdaemon.plist'}
        if (args.compiler_dir / 'a5shader/midgard-generic602').is_file():
            compiler_members.update({'a5shader/midgard-generic602','a5shader/generic602.json'})
            for profile_id in (603,604,605,606):
                name = f'a5shader/generic{profile_id}.json'
                if (args.compiler_dir / name).is_file():
                    compiler_members.add(name)
            if not args.installer_source:
                parser.error('automatic compiler requires --installer-source to check the real kernel preflight')
        actual = {str(p.relative_to(args.compiler_dir)) for p in args.compiler_dir.rglob('*') if not p.is_dir()}
        if actual != compiler_members:
            parser.error('unexpected compiler package members')
        for name in sorted(compiler_members):
            data = regular_bytes(args.compiler_dir / name,32*1024*1024)
            executable = not name.endswith(('.json','.plist'))
            if executable:
                arm64_macho(data,name)
            destination = COMPILER_PLIST_DEST if name.endswith('.plist') else '/usr/libexec/' + name
            entries.append((destination,data,0o755 if executable else 0o644))
    entries = [(path, data, mode, 0, 0) for path, data, mode in entries]
    directories = []
    app_xattrs = None
    if args.display_apps:
        app_files, directories, app_xattrs = display_app_entries(args.display_apps)
        entries.extend(app_files)
    compiled_directories=[]
    seen_stages=set()
    for publication,request in zip(args.compiled_stage,args.compiled_request):
        stage_files,stage_dirs=compiled_stage_entries(publication,request,args.output.parent/'.compiled-stage-validation')
        if publication.name in seen_stages:parser.error('duplicate compiled-stage identity')
        seen_stages.add(publication.name);entries.extend(stage_files)
        for directory in stage_dirs:
            if directory not in compiled_directories:compiled_directories.append(directory)
    extended = bool(args.compiler_dir or args.display_apps or args.compiled_stage)
    limit = 64*1024*1024 if extended else MAX_TOTAL
    if sum(len(data) for _, data, _, _, _ in entries) > limit:
        parser.error(f"payload exceeds {limit}-byte raw bound")
    lines = ["/* Generated local artifact: do not commit. */", "#define A5METAL_PAYLOAD_PRESENT 1"]
    packed_sizes = []
    for index, (_, data, _, _, _) in enumerate(entries):
        packed = data
        if extended:
            # Keep the original stream as a candidate: tuning can never grow
            # an entry. All candidates use the same standard zlib wrapper.
            candidates = [zlib.compress(data,9)]
            for memory,strategy in ((9,zlib.Z_DEFAULT_STRATEGY),(9,zlib.Z_FILTERED),
                                    (6,zlib.Z_DEFAULT_STRATEGY),(7,zlib.Z_DEFAULT_STRATEGY)):
                compressor = zlib.compressobj(9,zlib.DEFLATED,15,memory,strategy)
                candidates.append(compressor.compress(data) + compressor.flush())
            packed = min(candidates,key=len)
        compressed = len(packed) < len(data)
        packed = packed if compressed else data
        packed_sizes.append(len(packed) if compressed else 0)
        lines.append(f"static const unsigned char a5metal_payload_{index}[] = {{")
        lines.extend("\t" + ",".join(f"0x{x:02x}" for x in packed[i:i + 16]) + "," for i in range(0, len(packed), 16))
        if not packed:
            lines.append("\t0x00, /* nonnull sentinel for a zero-byte regular file */")
        lines.append("};")
    if extended and sum(packed_sizes[i] or len(d) for i,(_,d,_,_,_) in enumerate(entries)) > 10*1024*1024:
        parser.error('packed payload exceeds 10MiB bound')
    if directories:
        lines.append('#define A5METAL_DIRECTORIES_PRESENT 1')
        lines.append('static const struct a5metal_install_directory a5metal_install_directories[] = {')
        for path, mode, uid, gid in directories:
            lines.append(f'\t{{ {c_string(path)}, 0{mode:o}, {uid}U, {gid}U }},')
        lines.append('};')
    if compiled_directories:
        lines.append('#define A5METAL_COMPILED_DIRECTORIES_PRESENT 1')
        lines.append('static const struct a5metal_install_directory a5metal_install_compiled_directories[] = {')
        for path,mode,uid,gid in compiled_directories:
            lines.append(f'\t{{ {c_string(path)}, 0{mode:o}, {uid}U, {gid}U }},')
        lines.append('};')
    lines.append("static const struct a5metal_install_file a5metal_install_files[] = {")
    for index, (path, data, mode, uid, gid) in enumerate(entries):
        lines.append(f'\t{{ {c_string(path)}, a5metal_payload_{index}, {len(data)}U, 0{mode:o}, {packed_sizes[index]}U, {uid}U, {gid}U }},')
    lines.append("};")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n")
    if args.installer_source:
        check = subprocess.run([sys.executable,str(Path(__file__).with_name('test-a5xelte-display-app-policy.py')),
            '--installer',str(args.installer_source),'--payload',str(args.output),
            '--output',str(args.output.parent / '.payload-preflight'),'--preflight-only'],
            capture_output=True,text=True)
        if check.returncode:
            sys.stderr.write(check.stdout + check.stderr)
            parser.error('actual kernel rejected the generated payload; BOOT packaging stopped')
        sys.stderr.write(check.stdout)

    print(json.dumps({"output": str(args.output), "files": [{"path": p, "size": len(d), "mode": oct(m), "uid": u, "gid": g, "crc32": f"{zlib.crc32(d):08x}"} for p, d, m, u, g in entries], "bytes": sum(len(d) for _, d, _, _, _ in entries),
        'packed_bytes':sum(packed_sizes[i] or len(d) for i,(_,d,_,_,_) in enumerate(entries)), 'display_apps': list(DISPLAY_APPS) if args.display_apps else [], 'directories': [{'path':p,'mode':oct(m),'uid':u,'gid':g} for p,m,u,g in directories], 'compiled_stage_count':len(seen_stages), 'compiled_stages':sorted(seen_stages), 'compiled_directory_count':len(compiled_directories), 'compiled_directories':[{'path':p,'mode':oct(m),'uid':u,'gid':g} for p,m,u,g in compiled_directories], 'xattrs': app_xattrs}, indent=2))


if __name__ == "__main__":
    main()
