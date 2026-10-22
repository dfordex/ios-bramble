#!/usr/bin/env python3
"""Embed this project's signed Metal bundle in a private XNU include.

The output belongs in bsd/kern/A5XELTEMetalBundlePayload.inc of the local
XNU build tree. It is a generated binary artifact and must not be committed.
No device access or filesystem image modification is performed here.
"""
from __future__ import annotations

import argparse
import collections
import ctypes
import os
import stat
import json
from pathlib import Path
import plistlib
import struct
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


def regular_bytes(path: Path, maximum: int = MAX_FILE) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"regular file required: {path}")
    if not 0 < path.stat().st_size <= maximum:
        raise ValueError(f"file size outside 1..{maximum}: {path}")
    return path.read_bytes()


def arm64_macho(data: bytes, name: str) -> None:
    if len(data) < 32 or struct.unpack_from("<II", data) != (0xFEEDFACF, 0x0100000C):
        raise ValueError(f"thin arm64 Mach-O required: {name}")


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
    parser.add_argument('--display-apps', type=Path,
                        help='mounted source Applications; embeds only six fixed display bundles, requires installer support')
    args = parser.parse_args()
    if bool(args.probe) != bool(args.launch_plist):
        parser.error("--probe and --launch-plist must be provided together")
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
                if compiler_plist.get('ProgramArguments') != ['/usr/libexec/a5shader-compile','--selftest']:
                    parser.error('unexpected compiler launch arguments')
                if COMPILER_PLIST_DEST in jobs and jobs[COMPILER_PLIST_DEST] != compiler_plist:
                    parser.error('cache contains a different compiler job')
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
    extended = bool(args.compiler_dir or args.display_apps)
    limit = 64*1024*1024 if extended else MAX_TOTAL
    if sum(len(data) for _, data, _, _, _ in entries) > limit:
        parser.error(f"payload exceeds {limit}-byte raw bound")
    lines = ["/* Generated local artifact: do not commit. */", "#define A5METAL_PAYLOAD_PRESENT 1"]
    packed_sizes = []
    for index, (_, data, _, _, _) in enumerate(entries):
        packed = zlib.compress(data,9) if extended else data
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
    lines.append("static const struct a5metal_install_file a5metal_install_files[] = {")
    for index, (path, data, mode, uid, gid) in enumerate(entries):
        lines.append(f'\t{{ {c_string(path)}, a5metal_payload_{index}, {len(data)}U, 0{mode:o}, {packed_sizes[index]}U, {uid}U, {gid}U }},')
    lines.append("};")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n")
    print(json.dumps({"output": str(args.output), "files": [{"path": p, "size": len(d), "mode": oct(m), "uid": u, "gid": g, "crc32": f"{zlib.crc32(d):08x}"} for p, d, m, u, g in entries], "bytes": sum(len(d) for _, d, _, _, _ in entries),
        'packed_bytes':sum(packed_sizes[i] or len(d) for i,(_,d,_,_,_) in enumerate(entries)), 'display_apps': list(DISPLAY_APPS) if args.display_apps else [], 'directories': [{'path':p,'mode':oct(m),'uid':u,'gid':g} for p,m,u,g in directories], 'xattrs': app_xattrs}, indent=2))


if __name__ == "__main__":
    main()
