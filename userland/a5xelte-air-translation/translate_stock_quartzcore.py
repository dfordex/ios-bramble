#!/usr/bin/env python3
"""Translate bounded stock QuartzCore render pairs outside Git.

The tool does not package shaders or claim Mali executables for the additional
pairs. Its JSON checks reject a silent change of resource ABI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


DOWNSAMPLE_4_VERTEX_DESCRIPTOR = {
    "layouts": {"1": {"stride": 48, "step_function": "PerVertex", "step_rate": 1}},
    "attributes": {
        str(index): {"format": fmt, "offset": offset, "buffer_index": 1}
        for index, (fmt, offset) in enumerate([
            ("Float4", 0), ("Float2", 16), ("Float2", 24), ("Half4", 32)])
    },
}


def range_specialization(index: int, stage: str, buffer: int) -> dict:
    return {"id": index, "key": {"RangeAtBindOffset": {
        "stage": stage, "class": "Buffer", "index": buffer}},
        "size": 4, "default": 0, "unread_bits": 0}


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
    "downsample_4": {
        "vertex": "downsample_blur_vert_lph",
        "fragment": "downsample_4_frag_lph",
        "slots": [("Vertex", "Buffer", 2), ("Vertex", "Buffer", 3),
                  ("Fragment", "Buffer", 1), ("Fragment", "Buffer", 6),
                  ("Fragment", "Texture", 3), ("Fragment", "Sampler", 0)],
        "buffer_windows": [("UniformWords", 64), ("UniformWords", 16),
                           ("UniformWords", 72), ("UniformWords", 2)],
        "push": [("Vertex", 0, 8), ("Fragment", 64, 12)],
        "write_mask": 15,
        "sampled_texture": True,
        "vertex_descriptor": DOWNSAMPLE_4_VERTEX_DESCRIPTOR,
        "specialization": [
            [range_specialization(1, "Vertex", 2),
             range_specialization(2, "Vertex", 3)],
            [{"id": 0, "key": {"SamplerState": {
                "slot": {"stage": "Fragment", "class": "Sampler", "index": 0},
                "fields": 2147483655}}, "size": 4, "default": 0,
                "unread_bits": 4294967288},
             range_specialization(3, "Fragment", 1),
             range_specialization(4, "Fragment", 6)],
        ],
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
        if slot["class"] == "Sampler":
            if not spec.get("sampled_texture") or interface != {
                    "Sampler": {"compare": False, "coordinate_sensitive": True}}:
                raise ValueError(f"changed sampler interface: {slot}")
            continue
        access = interface.get("Buffer", interface.get("Texture", {})).get("access", {})
        if slot["class"] == "Texture" and spec.get("sampled_texture"):
            if interface != {"Texture": {"texture_type": "Type2D",
                    "sampled_type": "Float", "depth_compare": False,
                    "access": {"sample": True, "read": False, "write": False}}}:
                raise ValueError(f"changed sampled-texture interface: {slot}")
            continue
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
    result = {"resource_slots": slots, "buffer_windows": buffer_windows,
            "push_ranges": pushes,
            "color_format": "BGRA8Unorm", "color_write_rule": "0x2222"}
    if "specialization" in spec:
        specialization = [s["specialization"]["constants"] for s in meta["stages"]]
        if specialization != spec["specialization"]:
            raise ValueError("changed bind-time range or sampler specialization ABI")
        result["required_bind_specialization"] = specialization
        result["vertex_descriptor"] = spec["vertex_descriptor"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pair", choices=PAIRS)
    parser.add_argument("metallib", type=Path)
    parser.add_argument("output_prefix", type=Path)
    parser.add_argument("--translator", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--spirv-val", type=Path,
                        help="required real SPIRV-Tools validator; otherwise use "
                             "METAL2VULKAN_SPIRV_VAL or PATH")
    args = parser.parse_args()
    validator = args.spirv_val or os.environ.get("METAL2VULKAN_SPIRV_VAL") or \
        shutil.which("spirv-val")
    if not validator or not Path(validator).is_file():
        raise ValueError("spirv-val is required; give --spirv-val or install SPIRV-Tools")
    environment = os.environ.copy()
    environment["METAL2VULKAN_SPIRV_VAL"] = str(Path(validator).resolve())
    validator_version = subprocess.check_output(
        [environment["METAL2VULKAN_SPIRV_VAL"], "--version"], text=True).splitlines()[0]
    spec = PAIRS[args.pair]
    out = args.output_prefix.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    meta_path = out.with_name(out.name + "-meta.json")
    command = [
        str(args.translator), str(args.metallib), str(out) + ".spv",
        "--function", spec["vertex"], "--fragment", spec["fragment"],
        "--profile", str(args.profile), "--color-format", "0:BGRA8Unorm",
        "--emit-meta", str(meta_path),
    ]
    if "vertex_descriptor" in spec:
        descriptor_path = out.with_name(out.name + "-vertex-descriptor.json")
        descriptor_path.write_text(json.dumps(spec["vertex_descriptor"], indent=2) + "\n")
        command += ["--vertex-descriptor", str(descriptor_path)]
    # The translator validates every stage under the supplied profile's target
    # environments and enabled layout features before writing any stage. Its
    # default tolerates a missing validator, so resolve and require it above.
    subprocess.run(command, check=True, env=environment)
    meta = json.loads(meta_path.read_text())
    abi = check_meta(meta, spec)
    for stage in ("vert", "frag"):
        path = out.with_name(out.name + f".{stage}.spv")
        binary = path.read_bytes()
        if not binary.startswith(b"\x03\x02\x23\x07"):
            raise ValueError(f"{path} is not SPIR-V")
        abi[stage] = {"bytes": len(binary),
                      "sha256": hashlib.sha256(binary).hexdigest()}
    print(json.dumps({"pair": args.pair, "spirv_validator": validator_version,
                      "functions": [spec["vertex"],
                      spec["fragment"]], **abi}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"translation failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
