#!/usr/bin/env python3
"""Embed this project's signed Metal bundle in a private XNU include.

The output belongs in bsd/kern/A5XELTEMetalBundlePayload.inc of the local
XNU build tree. It is a generated binary artifact and must not be committed.
No device access or filesystem image modification is performed here.
"""
from __future__ import annotations

import argparse
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
    limit = 64*1024*1024 if args.compiler_dir else MAX_TOTAL
    if sum(len(data) for _, data, _ in entries) > limit:
        parser.error(f"payload exceeds {limit}-byte raw bound")
    lines = ["/* Generated local artifact: do not commit. */", "#define A5METAL_PAYLOAD_PRESENT 1"]
    packed_sizes = []
    for index, (_, data, _) in enumerate(entries):
        packed = zlib.compress(data,9) if args.compiler_dir else data
        compressed = len(packed) < len(data)
        packed = packed if compressed else data
        packed_sizes.append(len(packed) if compressed else 0)
        lines.append(f"static const unsigned char a5metal_payload_{index}[] = {{")
        lines.extend("\t" + ",".join(f"0x{x:02x}" for x in packed[i:i + 16]) + "," for i in range(0, len(packed), 16))
        lines.append("};")
    if args.compiler_dir and sum(packed_sizes[i] or len(d) for i,(_,d,_) in enumerate(entries)) > 10*1024*1024:
        parser.error('packed payload exceeds 10MiB bound')
    lines.append("static const struct a5metal_install_file a5metal_install_files[] = {")
    for index, (path, data, mode) in enumerate(entries):
        extra = f', {packed_sizes[index]}U' if args.compiler_dir else ''
        lines.append(f'\t{{ "{path}", a5metal_payload_{index}, {len(data)}U, 0{mode:o}{extra} }},')
    lines.append("};")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n")
    print(json.dumps({"output": str(args.output), "files": [{"path": p, "size": len(d), "mode": oct(m)} for p, d, m in entries], "bytes": sum(len(d) for _, d, _ in entries),
        'packed_bytes':sum(packed_sizes[i] or len(d) for i,(_,d,_) in enumerate(entries))}, indent=2))


if __name__ == "__main__":
    main()
