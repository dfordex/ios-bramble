#!/usr/bin/env python3
"""Cross-build the pinned AIR translator as an ARM64 iOS executable.

This uses Rust's real aarch64-apple-ios standard library and Apple's iPhoneOS
SDK. It does not modify the translator, install to a phone, sign an executable,
or bypass SPIR-V validation. Inputs, target std and Cargo dependencies must
already be available; Cargo runs offline and with its lock file enforced.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import struct
import subprocess


UPSTREAM_REVISION = "a2c440b8bcdcf20d34aa1694b61ae22c2a7ea68b"
TARGET = "aarch64-apple-ios"


def capture(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def verify_ios(path):
    data = path.read_bytes()
    if len(data) < 32:
        raise RuntimeError("truncated executable")
    magic, cpu, subtype, kind, commands, command_bytes, _, _ = struct.unpack_from(
        "<8I", data
    )
    if (magic, cpu, subtype, kind) != (0xFEEDFACF, 0x0100000C, 0, 2):
        raise RuntimeError("expected thin ARM64 (not arm64e) MH_EXECUTE Mach-O")
    end = 32 + command_bytes
    if end > len(data):
        raise RuntimeError("truncated Mach-O commands")
    offset = 32
    builds = []
    dylibs = []
    for _ in range(commands):
        if offset + 8 > end:
            raise RuntimeError("invalid Mach-O command range")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > end:
            raise RuntimeError("invalid Mach-O command size")
        if command == 0x32:  # LC_BUILD_VERSION
            if size < 24:
                raise RuntimeError("truncated LC_BUILD_VERSION")
            platform, minimum, sdk, _ = struct.unpack_from("<4I", data, offset + 8)
            if platform != 2:  # PLATFORM_IOS, not MACOS or IOSSIMULATOR
                raise RuntimeError("executable is not built for the iOS device platform")
            if minimum != 16 << 16:
                raise RuntimeError("deployment minimum must be exactly iOS 16.0")
            builds.append({"platform": platform, "minos": minimum, "sdk": sdk})
        if command in (0xC, 0x80000018, 0x8000001F):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            if not 24 <= name_offset < size:
                raise RuntimeError("invalid dylib load command")
            name = data[offset + name_offset:offset + size].split(b"\0", 1)[0]
            dylibs.append(name.decode("utf-8", errors="strict"))
        offset += size
    if len(builds) != 1 or offset != end:
        raise RuntimeError("expected one verified iOS build-version command")
    if dylibs != ["/usr/lib/libSystem.B.dylib"]:
        raise RuntimeError("review unexpected native runtime dependencies: " + repr(dylibs))
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "linked_dylibs": dylibs, **builds[0]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path, help="pinned metal2vulkan checkout")
    parser.add_argument("output", type=pathlib.Path, help="private build/output directory")
    parser.add_argument("--cargo", default="cargo", help="Cargo/rustup proxy executable")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    cargo = shutil.which(args.cargo)
    if not cargo:
        raise RuntimeError("Cargo not found; supply --cargo or configure PATH")
    revision = capture(["git", "-C", str(source), "rev-parse", "HEAD"])
    if revision != UPSTREAM_REVISION:
        raise RuntimeError("translator revision differs from the reviewed upstream pin")
    if capture(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"]):
        raise RuntimeError("translator tracked sources are modified")
    if not (source / "Cargo.lock").is_file():
        raise RuntimeError("the dependency lock file is required")
    sdk = capture(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])
    sdk_version = capture(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])
    env = dict(os.environ)
    env.update({
        "CARGO_TARGET_DIR": str(output / "cargo-target"),
        "SDKROOT": sdk,
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "RUSTFLAGS": "-Dwarnings -C target-cpu=cortex-a53",
        "SOURCE_DATE_EPOCH": capture(["git", "-C", str(source), "show", "-s", "--format=%ct"]),
    })
    # The proxies locate rustc using their sibling directory; retain the
    # caller's explicit CARGO_HOME/RUSTUP_HOME rather than changing global state.
    env["PATH"] = str(pathlib.Path(cargo).parent) + os.pathsep + env.get("PATH", "")
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        cargo, "build", "--manifest-path", str(source / "Cargo.toml"),
        "--offline", "--locked", "--release", "--package", "metal2vulkan",
        "--features", "cli", "--target", TARGET, "--bin", "metal2vulkan",
    ], env=env, check=True)
    compiled = output / "cargo-target" / TARGET / "release" / "metal2vulkan"
    result = verify_ios(compiled)
    artifact = output / "metal2vulkan-ios"
    shutil.copy2(compiled, artifact)
    result.update({
        "artifact": str(artifact), "target": TARGET, "source_revision": revision,
        "cargo_lock_sha256": hashlib.sha256((source / "Cargo.lock").read_bytes()).hexdigest(),
        "sdk_path": sdk, "sdk_version": sdk_version,
        "rustc": capture(["rustc", "-Vv"], env=env),
        "rustflags": env["RUSTFLAGS"], "signed_for_install": False,
        "runtime_validation": "Require an iOS spirv-val and its actual PASS; never accept not found.",
        "device_execution_verified": False,
    })
    (output / "air-translator-build.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
