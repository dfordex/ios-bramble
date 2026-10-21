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


BUNDLE_DEST = "/System/Library/Extensions/A5MaliMetal.bundle"
PROBE_DEST = "/usr/libexec/a5mali-metal-probe"
PLIST_DEST = "/System/Library/LaunchDaemons/com.orhunnx.a5mali-metal-probe.plist"
CACHE_DEST = "/System/Library/xpc/launchd.plist"
MAX_FILE = 2 * 1024 * 1024
MAX_TOTAL = 4 * 1024 * 1024


def regular_bytes(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"regular file required: {path}")
    if not 0 < path.stat().st_size <= MAX_FILE:
        raise ValueError(f"file size outside 1..{MAX_FILE}: {path}")
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
    args = parser.parse_args()
    if bool(args.probe) != bool(args.launch_plist):
        parser.error("--probe and --launch-plist must be provided together")
    if args.launchd_cache and not args.launch_plist:
        parser.error("--launchd-cache requires --probe and --launch-plist")
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
            patched_cache = plistlib.dumps(cache, fmt=plistlib.FMT_BINARY, sort_keys=False)
            if len(patched_cache) > MAX_FILE:
                parser.error("patched launchd cache exceeds 2 MiB bound")
            entries.append((CACHE_DEST, patched_cache, 0o644))
    if sum(len(data) for _, data, _ in entries) > MAX_TOTAL:
        parser.error("payload exceeds 4 MiB bound")
    lines = ["/* Generated local artifact: do not commit. */", "#define A5METAL_PAYLOAD_PRESENT 1"]
    for index, (_, data, _) in enumerate(entries):
        lines.append(f"static const unsigned char a5metal_payload_{index}[] = {{")
        lines.extend("\t" + ",".join(f"0x{x:02x}" for x in data[i:i + 16]) + "," for i in range(0, len(data), 16))
        lines.append("};")
    lines.append("static const struct a5metal_install_file a5metal_install_files[] = {")
    for index, (path, data, mode) in enumerate(entries):
        lines.append(f'\t{{ "{path}", a5metal_payload_{index}, {len(data)}U, 0{mode:o} }},')
    lines.append("};")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n")
    print(json.dumps({"output": str(args.output), "files": [{"path": p, "size": len(d), "mode": oct(m)} for p, d, m in entries], "bytes": sum(len(d) for _, d, _ in entries)}, indent=2))


if __name__ == "__main__":
    main()
