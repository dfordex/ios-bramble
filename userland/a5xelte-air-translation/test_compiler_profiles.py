#!/usr/bin/env python3
"""Validate real staged AIR profiles, compiler metadata and rejection gates.

All generated/proprietary artifacts are written to the supplied private output
directory, never beside this source. Requires real SPIRV-Tools and Mesa tools.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


EXPECTED = {
    "read_surf": {
        "vert": (208, 1, "c6ee709a69f08c5d556399155fd881b648f50ba368f630ccf315824aa467eef7"),
        "frag": (1232, 6, "a87ae5aef8fd86863bf2d62b57924243107defddcb2da91ae172affc646a3b23"),
    },
    "downsample_4": {
        "vert": (2048, 8, "f5556b29f212c3674cb16b166a7dbf93671b4c27b7c65e54b78d77a2837f2be1"),
        "frag": (3472, 7, "1771f55d5bf91525734b33166e001bdf2b402e7467988c366016c8c1f8ff2a82"),
    },
}


def run(command: list[str], log: Path, success: bool = True) -> str:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    log.write_text(result.stdout)
    if (result.returncode == 0) != success:
        raise RuntimeError(f"unexpected exit {result.returncode}: {command}; see {log}")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesa_build", type=Path)
    parser.add_argument("metallib", type=Path)
    parser.add_argument("translator", type=Path)
    parser.add_argument("profile", type=Path)
    parser.add_argument("validator", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    out = args.output_dir.resolve()
    source = Path(__file__).resolve().parent
    if out == source or source in out.parents:
        raise ValueError("outputs must stay outside the source directory")
    out.mkdir(parents=True, exist_ok=True)
    compiler = out / "spirv-pair"
    run([sys.executable, str(source / "build_local.py"),
         str(args.mesa_build.resolve()), str(compiler)], out / "build.log")
    records = {}
    for pair, stages in EXPECTED.items():
        prefix = out / pair
        translation = run([
            sys.executable, str(source / "translate_stock_quartzcore.py"), pair,
            str(args.metallib.resolve()), str(prefix),
            "--translator", str(args.translator.resolve()),
            "--profile", str(args.profile.resolve()),
            "--spirv-val", str(args.validator.resolve()),
        ], out / f"{pair}-translation.log")
        if "spirv-val vulkan1.2: PASS" not in translation:
            raise RuntimeError(f"{pair}: missing actual profile validation result")
        inputs = [str(prefix) + f".{s}.spv" for s in ("vert", "frag")]
        outputs = [str(prefix) + f".{s}.midgard" for s in ("vert", "frag")]
        command = [str(compiler), *inputs, *outputs]
        if pair == "downsample_4":
            command.append(pair)
        log = run(command, out / f"{pair}-midgard.log")
        records[pair] = {}
        for stage, output in zip(("vert", "frag"), outputs):
            binary = Path(output).read_bytes()
            size, regs, sha = stages[stage]
            if len(binary) != size or hashlib.sha256(binary).hexdigest() != sha:
                raise RuntimeError(f"{pair}/{stage}: authenticated binary changed")
            expected = (f"{output}: Midgard bytes={size} first_tag=5 textures=0 "
                        f"work_regs={regs} tls=0 wls=0")
            if expected not in log:
                raise RuntimeError(f"{pair}/{stage}: renderer metadata changed")
            records[pair][stage] = {
                "bytes": size, "work_regs": regs, "first_tag": 5,
                "tls": 0, "wls": 0, "sha256": sha,
                "spirv_sha256": hashlib.sha256(
                    Path(str(prefix) + f".{stage}.spv").read_bytes()).hexdigest(),
            }

    # A malformed bound is rejected by real SPIRV-Tools, independently of the
    # compiler's profile fingerprint. Never invoke a permissive validation shim.
    malformed = bytearray((out / "downsample_4.vert.spv").read_bytes())
    malformed[12:16] = (1).to_bytes(4, "little")
    bad = out / "invalid-bound.vert.spv"
    bad.write_bytes(malformed)
    run([str(args.validator.resolve()), "--target-env", "vulkan1.2",
         "--uniform-buffer-standard-layout", str(bad)], out / "invalid-validation.log", False)

    # The stage compiler must reject modified modules and a valid pair used
    # under the wrong fixed-resource profile before writing either shader.
    rejects = [
        ("modified", bad, out / "downsample_4.frag.spv", True),
        ("wrong-profile", out / "downsample_4.vert.spv", out / "downsample_4.frag.spv", False),
    ]
    for name, vert, frag, downsample in rejects:
        vs, fs = out / f"{name}.vert.bin", out / f"{name}.frag.bin"
        for path in (vs, fs):
            path.unlink(missing_ok=True)
        command = [str(compiler), str(vert), str(frag), str(vs), str(fs)]
        if downsample:
            command.append("downsample_4")
        rejected = run(command, out / f"{name}.log", False)
        if "unsupported SPIR-V module" not in rejected or vs.exists() or fs.exists():
            raise RuntimeError(f"{name}: rejection wrote output or bypassed fingerprint")

    missing = run([
        sys.executable, str(source / "translate_stock_quartzcore.py"), "read_surf",
        str(args.metallib.resolve()), str(out / "missing-validator"),
        "--translator", str(args.translator.resolve()),
        "--profile", str(args.profile.resolve()),
        "--spirv-val", str(out / "nonexistent-spirv-val"),
    ], out / "missing-validator.log", False)
    if "spirv-val is required" not in missing:
        raise RuntimeError("missing validator was not rejected before translation")
    (out / "compiler_profiles.json").write_text(json.dumps(records, indent=2) + "\n")
    print("PASS: actual AIR/SPIR-V validation, four authenticated Midgard stages, "
          "zero TLS/WLS, malformed-module/profile and missing-validator rejection")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
