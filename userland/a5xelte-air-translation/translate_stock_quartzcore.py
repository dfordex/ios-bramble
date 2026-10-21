#!/usr/bin/env python3
"""Translate two bounded stock QuartzCore render pairs outside Git.

The tool does not package shaders or claim a Mali executable for the second
pair. Its JSON checks reject a silent change of resource ABI.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


PAIRS = {
    "read_surf": {
        "vertex": "read_surf_vert",
        "fragment": "read_surf_frag",
        "slots": [("Fragment", "Texture", 0)],
        "buffer_windows": [],
        "push": [("Fragment", 64, 4)],
        "write_mask": 15,
    },
    "buffer_image_blit": {
        "vertex": "buffer_image_blit_vert_lpf",
        "fragment": "buffer_image_blit_frag_lpf",
        "slots": [("Vertex", "Buffer", 1), ("Vertex", "Buffer", 2),
                  ("Fragment", "Buffer", 1), ("Fragment", "Buffer", 9)],
        "buffer_windows": [("Storage", "Whole"), ("UniformWords", 64),
                           ("UniformWords", 16), ("Storage", "Whole")],
        "push": [("Vertex", 0, 8), ("Fragment", 64, 12)],
        "write_mask": 15,
    },
}


def check_meta(meta: dict, spec: dict) -> dict:
    if meta.get("kind") != "render":
        raise ValueError("not a render pipeline")
    stages = [(s["stage"], s["entry_point"]) for s in meta["stages"]]
    if stages != [("vert", "main"), ("frag", "main")]:
        raise ValueError(f"changed stage entry points: {stages}")
    slots = []
    buffer_windows = []
    for slot, interface in meta["interface"]["slots"]:
        slots.append((slot["stage"], slot["class"], slot["index"]))
        access = interface.get("Buffer", interface.get("Texture", {})).get("access", {})
        if not access.get("read") or access.get("write"):
            raise ValueError(f"unexpected writable/non-readable slot: {slot}")
        if slot["class"] == "Texture" and access.get("sample"):
            raise ValueError("read_surf Texture0 must use integer read, not sampling")
        if slot["class"] == "Buffer":
            resource = interface["Buffer"]
            window = resource["window"]
            buffer_windows.append((resource["form"]["Descriptor"],
                                   "Whole" if window == "Whole" else
                                   window["Bounded"]["len"]))
    if slots != spec["slots"]:
        raise ValueError(f"changed resource slots: {slots}")
    if buffer_windows != spec["buffer_windows"]:
        raise ValueError(f"changed buffer windows: {buffer_windows}")
    pushes = [("Vertex" if p["stages"] == 1 else "Fragment",
               p["offset"], p["size"])
              for p in meta["layout"]["push_constants"]]
    if pushes != spec["push"]:
        raise ValueError(f"changed push ABI: {pushes}")
    graphics = meta["graphics"]
    colors = graphics["color_attachments"]
    if len(colors) != 1 or colors[0]["format"] != 44 or \
       colors[0]["write_mask"] != spec["write_mask"] or \
       graphics["rasterization_samples"] != 1:
        raise ValueError("changed BGRA8 single-sample attachment ABI")
    if graphics["color_write_rules"] != [[0, 0x2222]]:
        raise ValueError("changed BGRA8 color write rule")
    return {"resource_slots": slots, "buffer_windows": buffer_windows,
            "push_ranges": pushes,
            "color_format": "BGRA8Unorm", "color_write_rule": "0x2222"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pair", choices=PAIRS)
    parser.add_argument("metallib", type=Path)
    parser.add_argument("output_prefix", type=Path)
    parser.add_argument("--translator", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    args = parser.parse_args()
    spec = PAIRS[args.pair]
    out = args.output_prefix.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    meta_path = out.with_name(out.name + "-meta.json")
    subprocess.run([
        str(args.translator), str(args.metallib), str(out) + ".spv",
        "--function", spec["vertex"], "--fragment", spec["fragment"],
        "--profile", str(args.profile), "--color-format", "0:BGRA8Unorm",
        "--emit-meta", str(meta_path), "--no-spirv-val",
    ], check=True)
    meta = json.loads(meta_path.read_text())
    abi = check_meta(meta, spec)
    for stage in ("vert", "frag"):
        path = out.with_name(out.name + f".{stage}.spv")
        binary = path.read_bytes()
        if not binary.startswith(b"\x03\x02\x23\x07"):
            raise ValueError(f"{path} is not SPIR-V")
        abi[stage] = {"bytes": len(binary),
                      "sha256": hashlib.sha256(binary).hexdigest()}
    print(json.dumps({"pair": args.pair, "functions": [spec["vertex"],
                      spec["fragment"]], **abi}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"translation failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
