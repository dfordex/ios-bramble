#!/usr/bin/env python3
"""Exercise the native orchestration with real macOS tools and stock AIR.

Only the runner is built for this host test. Supply actual host metal2vulkan,
spirv-val and midgard-compile executables; no stand-in validator/compiler is
generated. Inputs and all generated shaders remain in --work-dir or the given
metallib location. A host PASS does not establish iOS execution or GPU pixels.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile


def invoke(command: list[str], *, success: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(command, capture_output=True, text=True, timeout=90)
    if (result.returncode == 0) != success:
        raise AssertionError(f"unexpected status {result.returncode}: {command}\n{result.stdout}\n{result.stderr}")
    return result


def require_text(result: subprocess.CompletedProcess, text: str) -> None:
    if text not in result.stdout + result.stderr:
        raise AssertionError(f"missing actual result marker {text!r}\n{result.stdout}\n{result.stderr}")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stage_tool(source: Path, output: Path, library_dir: Path, seen: set[Path]) -> None:
    source = source.resolve(strict=True)
    shutil.copyfile(source, output)
    output.chmod(0o755)
    if source in seen:
        return
    seen.add(source)
    # Homebrew's real spirv-val bottle has @rpath/../lib dependencies. Copy
    # their original libraries into the equivalent private test layout.
    info = invoke(["otool", "-L", str(source)]).stdout
    for line in info.splitlines()[1:]:
        dependency = line.strip().split(" (", 1)[0]
        if not dependency.startswith(("@rpath/", "@loader_path/")):
            continue
        name = Path(dependency).name
        choices = [source.parent.parent / "lib" / name, source.parent / name]
        if dependency.startswith("@loader_path/"):
            choices.insert(0, source.parent / dependency.removeprefix("@loader_path/"))
        library = next((path for path in choices if path.is_file()), None)
        if library is None:
            raise ValueError(f"cannot stage actual runtime library {dependency} from {source}")
        stage_tool(library, library_dir / name, library_dir, seen)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("translator", "spirv-val", "midgard", "metallib", "profile"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--runner-source", type=Path, default=Path(__file__).with_name("a5shader_compile.m"))
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="a5shader-host-regression-"))
    work.mkdir(parents=True, exist_ok=True)
    # Refuse reusing a test cache, so positive tests prove fresh compilation.
    if any(work.iterdir()):
        parser.error("--work-dir must be empty; previous evidence is retained")
    tools, libraries, cache = work / "tools", work / "lib", work / "cache"
    tools.mkdir(); libraries.mkdir()
    seen: set[Path] = set()
    for source, name in ((args.translator, "metal2vulkan"), (args.spirv_val, "spirv-val"), (args.midgard, "midgard-compile")):
        stage_tool(source, tools / name, libraries, seen)
    shutil.copyfile(args.profile.resolve(strict=True), tools / "profile.json")
    wrapper = Path(__file__).resolve().parents[1] / "translate_stock_quartzcore.py"
    profiles = runpy.run_path(str(wrapper))["PAIRS"]
    expected = runpy.run_path(str(wrapper.with_name("test_compiler_profiles.py")))["EXPECTED"]
    pairs = {name: profiles[name] for name in ("read_surf", "downsample_4")}
    pairs_data = json.dumps(pairs, separators=(",", ":")).encode()
    (tools / "pairs.json").write_bytes(pairs_data)
    runner = work / "a5shader-compile-host"
    invoke([
        "xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-Os",
        "-DA5_SHADER_HOST_TEST=1", f'-DA5_TEST_TOOLS="{tools}"',
        f'-DA5_TEST_CACHE="{cache}"', f'-DA5_TEST_LIBRARY="{args.metallib.resolve(strict=True)}"',
        str(args.runner_source.resolve(strict=True)), "-framework", "Foundation", "-o", str(runner),
    ])
    results: list[dict] = []

    first = invoke([str(runner), "--selftest"])
    (work / "fresh-run.log").write_text(first.stdout + first.stderr)
    if first.stderr.count("COMPILED pair=") != 2 or first.stderr.count("CACHE HIT pair=") != 2:
        raise AssertionError("selftest did not actually compile both pairs and reuse both caches")
    reports = {}
    for report_path in cache.glob("*/report.json"):
        report = json.loads(report_path.read_text())
        pair = report["pair"]
        if pair not in pairs or pair in reports:
            raise AssertionError("unexpected or duplicate compiled pair")
        for stage in ("vert", "frag"):
            path = report_path.parent / f"shader.{stage}.midgard"
            binary = path.read_bytes()
            if len(binary) != report[stage]["bytes"] or sha(binary) != report[stage]["sha256"]:
                raise AssertionError("compiled binary/report disagree")
            size, _registers, digest = expected[pair][stage]
            if len(binary) != size or sha(binary) != digest:
                raise AssertionError(f"{pair}/{stage}: authenticated compiler output changed")
            if not binary or len(binary) % 16:
                raise AssertionError("invalid Midgard output size")
            spv = report_path.parent / f"shader.{stage}.spv"
            if not spv.read_bytes().startswith(b"\x03\x02\x23\x07"):
                raise AssertionError("translator did not produce SPIR-V")
            invoke([str(tools / "spirv-val"), "--target-env", "vulkan1.2",
                    "--uniform-buffer-standard-layout", str(spv)])
        require_text(subprocess.CompletedProcess([], 0, (report_path.parent / "air.log").read_text(), ""),
                     "spirv-val vulkan1.2: PASS")
        reports[pair] = report_path
        results.append({"test": "real_compile_and_validate", "pair": pair,
                        "vert_bytes": report["vert"]["bytes"], "frag_bytes": report["frag"]["bytes"],
                        "vert_sha256": report["vert"]["sha256"], "frag_sha256": report["frag"]["sha256"]})
    if set(reports) != set(pairs):
        raise AssertionError("both compiled-pair reports were not published")

    timestamps = {path: path.stat().st_mtime_ns for directory in (p.parent for p in reports.values())
                  for path in directory.iterdir()}
    second = invoke([str(runner), "--selftest"])
    (work / "cache-reuse.log").write_text(second.stdout + second.stderr)
    if second.stderr.count("CACHE HIT pair=") != 4 or "COMPILED pair=" in second.stderr:
        raise AssertionError("second selftest unexpectedly recompiled")
    if any(path.stat().st_mtime_ns != timestamp for path, timestamp in timestamps.items()):
        raise AssertionError("cache reuse changed a published artifact")
    results.append({"test": "cache_reuse", "hits": 4, "artifact_mtimes_unchanged": True})

    original = reports["read_surf"].parent / "shader.vert.midgard"
    saved = original.read_bytes()
    original.write_bytes(bytes([saved[0] ^ 1]) + saved[1:])
    rejection = invoke([str(runner), "--pair", "read_surf"], success=False)
    require_text(rejection, "cache output digest mismatch")
    original.write_bytes(saved)
    (work / "corrupt-cache.log").write_text(rejection.stdout + rejection.stderr)
    results.append({"test": "corrupt_cache_rejected", "status": rejection.returncode})

    invalid = work / "invalid-magic.spv"
    valid_spv = reports["downsample_4"].parent / "shader.frag.spv"
    invalid.write_bytes(b"\0\0\0\0" + valid_spv.read_bytes()[4:])
    rejected_spv = invoke([str(tools / "spirv-val"), "--target-env", "vulkan1.2",
                           "--uniform-buffer-standard-layout", str(invalid)], success=False)
    if not rejected_spv.stderr.strip():
        raise AssertionError("real validator rejected without a diagnostic")
    (work / "invalid-spirv.log").write_text(rejected_spv.stdout + rejected_spv.stderr)
    results.append({"test": "real_validator_rejects_corrupt_spirv", "status": rejected_spv.returncode,
                    "diagnostic": rejected_spv.stderr.strip()})

    # This is the real validator disappearing, not a fake PASS/failure tool.
    validator = tools / "spirv-val"
    absent = tools / ".spirv-val-unavailable"
    validator.rename(absent)
    missing = invoke([str(runner), "--pair", "read_surf"], success=False)
    absent.rename(validator)
    require_text(missing, "invalid regular file:")
    require_text(missing, "spirv-val")
    (work / "missing-validator.log").write_text(missing.stdout + missing.stderr)
    results.append({"test": "mandatory_validator_missing_rejected", "status": missing.returncode})

    # Exercise metadata rejection after genuine AIR translation/validation.
    pairs["downsample_4"]["buffer_windows"][0] = ["UniformWords", 60]
    (tools / "pairs.json").write_text(json.dumps(pairs))
    bad_abi = invoke([str(runner), "--pair", "downsample_4"], success=False)
    require_text(bad_abi, "changed resource ABI")
    (tools / "pairs.json").write_bytes(pairs_data)
    (work / "changed-resource-abi.log").write_text(bad_abi.stdout + bad_abi.stderr)
    if set(cache.glob("*/report.json")) != set(reports.values()) or list(cache.glob(".work-*")):
        raise AssertionError("failed compilation published a cache or left active workspace")
    results.append({"test": "actual_metadata_abi_change_rejected", "status": bad_abi.returncode})

    summary = {"host_execution_verified": True, "device_execution_verified": False,
               "work_dir": str(work), "tests": results}
    (work / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
