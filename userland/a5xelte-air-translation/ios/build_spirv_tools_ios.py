#!/usr/bin/env python3
"""Build the unmodified Khronos spirv-val CLI for arm64 iOS16+, not macOS.

Requires Xcode's iphoneos SDK, CMake, Ninja and Python3.12+. No device action.
The SPIRV-Tools core is linked statically; only the iOS system C++/C runtime
remain dynamic. Upstream suppresses CLI targets for iOS packaging, so build
its static target and link its original four spirv-val CLI sources directly.
No validation code, options or return codes are replaced or weakened.

Example, fetch verified upstream sources into a private build directory:
  python3 build_spirv_tools_ios.py --fetch --work-dir /private/tmp/a5xelte-ondevice-compiler

Or provide existing source directories with both --tools-source and
--headers-source. Those directories are trusted local inputs; --fetch verifies
the pinned source archives. Generated sources, archives and executables stay
under --work-dir, outside the source repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import urllib.request


TOOLS_TAG = "vulkan-sdk-1.4.363.0"
TOOLS_SHA256 = "e6c83a215538fbfd265ccf398d3877985055df1273dbed73912bd05307664688"
HEADERS_REV = "496543121ce6419f23d6fa5d7194ba66c36212d2"
HEADERS_SHA256 = "a9bb9c48713245eacf97cc539b6f1d45405a92d8813f8b82e635f0a085ee9898"
SYSTEM_LIBRARIES = {"/usr/lib/libc++.1.dylib", "/usr/lib/libSystem.B.dylib"}


def run(command: list[str]) -> None:
    print("+", subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, check=True)


def capture(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()


def fetch_source(work: Path, project: str, revision: str, digest: str) -> Path:
    url = f"https://github.com/KhronosGroup/{project}/archive/{revision}.tar.gz"
    archive = work / "downloads" / f"{project}-{revision}.tar.gz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        temporary = archive.with_suffix(".partial")
        request = urllib.request.Request(url, headers={"User-Agent": "a5xelte-ios-build"})
        with urllib.request.urlopen(request, timeout=90) as response:
            with temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise ValueError(f"upstream archive checksum mismatch: {archive}")
    destination = work / "src" / f"{project}-{revision}"
    if not destination.exists():
        # extractall's data filter rejects links escaping the extraction tree.
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as source:
            roots = {Path(member.name).parts[0] for member in source.getmembers()}
            if roots != {destination.name}:
                raise ValueError(f"unexpected source archive root: {roots}")
            source.extractall(destination.parent, filter="data")
    return destination


def inspect_ios_executable(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError("truncated Mach-O")
    magic, cpu, subtype, kind, count, command_bytes, _, _ = struct.unpack_from(
        "<8I", data
    )
    if (magic, cpu, subtype & 0xFFFFFF, kind) != (0xFEEDFACF, 0x0100000C, 0, 2):
        raise ValueError("expected a thin arm64 executable, excluding arm64e/simulator")
    if command_bytes > len(data) - 32:
        raise ValueError("truncated Mach-O load commands")
    offset, build, dependencies = 32, None, []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > 32 + command_bytes:
            raise ValueError("invalid Mach-O load command")
        if command == 0x32:  # LC_BUILD_VERSION, platform2 is device iOS
            platform, minimum, sdk = struct.unpack_from("<III", data, offset + 8)
            if platform != 2 or minimum != 16 << 16:
                raise ValueError(f"wrong platform/minimum: {platform}/{minimum:#x}")
            build = {"platform": "iOS", "minimum": "16.0", "sdk_packed": sdk}
        elif command in (0xC, 0x80000018, 0x8000001F):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            if not 24 <= name_offset < size:
                raise ValueError("invalid dylib load command")
            dependencies.append(data[offset + name_offset : offset + size].split(b"\0")[0].decode())
        offset += size
    if build is None or set(dependencies) != SYSTEM_LIBRARIES:
        raise ValueError(f"unexpected platform/dynamic dependencies: {build}/{dependencies}")
    return {**build, "architecture": "arm64", "dependencies": dependencies}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=Path("/private/tmp/a5xelte-ondevice-compiler"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--tools-source", type=Path)
    parser.add_argument("--headers-source", type=Path)
    parser.add_argument("--fetch", action="store_true", help="fetch checksum-pinned official sources")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 4))
    args = parser.parse_args()
    if sys.version_info < (3, 12):
        parser.error("Python3.12+ is required for safe tar extraction")
    if args.jobs < 1 or args.jobs > 64:
        parser.error("--jobs must be1..64")
    if bool(args.tools_source) != bool(args.headers_source):
        parser.error("provide both source directories")
    if args.fetch and args.tools_source:
        parser.error("choose --fetch or local source directories")
    if not args.fetch and not args.tools_source:
        parser.error("provide --fetch or both local source directories")
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output = (args.output or work / "spirv-val").resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if args.fetch:
        tools = fetch_source(work, "SPIRV-Tools", TOOLS_TAG, TOOLS_SHA256)
        headers = fetch_source(work, "SPIRV-Headers", HEADERS_REV, HEADERS_SHA256)
    else:
        tools, headers = args.tools_source.resolve(), args.headers_source.resolve()
    if not (tools / "tools/val/val.cpp").is_file():
        parser.error("SPIRV-Tools source directory lacks the real validator CLI")
    deps = (tools / "DEPS").read_text()
    if not re.search(r"['\"]spirv_headers_revision['\"]\s*:\s*['\"]" + HEADERS_REV, deps):
        parser.error("SPIRV-Tools DEPS does not match the pinned headers revision")
    if not (headers / "include/spirv/unified1/spirv.core.grammar.json").is_file():
        parser.error("SPIRV-Headers source directory lacks the SPIR-V grammar")
    sdk = capture("xcrun", "--sdk", "iphoneos", "--show-sdk-path")
    cc = capture("xcrun", "--sdk", "iphoneos", "--find", "clang")
    cxx = capture("xcrun", "--sdk", "iphoneos", "--find", "clang++")
    build = work / "build-spirv-ios"
    run([
        "cmake", "-S", str(tools), "-B", str(build), "-G", "Ninja",
        "-DCMAKE_SYSTEM_NAME=iOS", f"-DCMAKE_OSX_SYSROOT={sdk}",
        "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0",
        "-DCMAKE_BUILD_TYPE=MinSizeRel", f"-DCMAKE_C_COMPILER={cc}",
        f"-DCMAKE_CXX_COMPILER={cxx}", "-DCMAKE_C_FLAGS=-march=armv8-a",
        "-DCMAKE_CXX_FLAGS=-march=armv8-a", "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
        "-DBUILD_SHARED_LIBS=OFF", "-DSPIRV_TOOLS_BUILD_STATIC=ON",
        "-DSPIRV_SKIP_TESTS=ON", "-DSPIRV_SKIP_EXECUTABLES=ON",
        "-DSPIRV_TOOLS_USE_MIMALLOC=OFF", f"-DSPIRV-Headers_SOURCE_DIR={headers}",
        f"-DPython3_EXECUTABLE={sys.executable}",
    ])
    run(["cmake", "--build", str(build), "--target", "SPIRV-Tools-static", "--parallel", str(args.jobs)])
    cli = ["tools/val/val.cpp", "tools/util/flags.cpp", "tools/util/cli_consumer.cpp", "tools/io.cpp"]
    run([
        cxx, "-target", "arm64-apple-ios16.0", "-isysroot", sdk, "-march=armv8-a",
        "-std=c++17", "-Os", "-DNDEBUG", "-Wl,-dead_strip",
        f"-I{tools}", f"-I{tools / 'include'}", f"-I{build}", f"-I{headers / 'include'}",
        *[str(tools / source) for source in cli],
        str(build / "source/libSPIRV-Tools.a"), "-o", str(output),
    ])
    # Strip local symbols while preserving the CLI and complete validator.
    run(["xcrun", "strip", "-x", str(output)])
    metadata = inspect_ios_executable(output)
    license_dir = work / "licenses"
    license_dir.mkdir(exist_ok=True)
    for name, source in (("SPIRV-Tools", tools), ("SPIRV-Headers", headers)):
        shutil.copyfile(source / "LICENSE", license_dir / f"{name}.LICENSE")
    metadata.update({
        "tools_tag": TOOLS_TAG, "tools_archive_sha256": TOOLS_SHA256,
        "headers_revision": HEADERS_REV, "headers_archive_sha256": HEADERS_SHA256,
        "archive_verified": args.fetch, "tools_source": str(tools), "headers_source": str(headers),
        "output": str(output), "bytes": output.stat().st_size, "static_spirv_tools": True,
        "compiler": capture(cxx, "--version"), "device_runtime_verified": False,
    })
    output.with_name(output.name + ".build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))
    print("Built genuine iOS spirv-val. Runtime validation and device signing remain separate steps.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
