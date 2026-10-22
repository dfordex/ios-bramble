#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read-only, UUID-bound regression for stock QuartzCore FP16 selection.

The operator supplies an extracted image. No Apple bytes are emitted or stored.
This checks the real instruction contract and table, not GPU execution.
"""
import argparse
import importlib.util
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("quartzcore", type=Path)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location(
        "qc_coverage", here / "a5mali-quartzcore-coverage.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    image = module.Image(args.quartzcore)
    # Constructor: query native FP16, OR Apple1, materialize capability bit20.
    # get_pipeline_spec moves bit20 into FragmentShader::Spec bit4.
    # create_fragment_shader indexes the stock 2x2 precision table.
    instructions = {
        0x1884889EC: 0x94051E2D,
        0x1884889F0: 0x2A1C0008,
        0x1884889F4: 0x36000068,
        0x1884889F8: 0x52A00208,
        0x188488A50: 0xB90A3EA8,
        0x188483908: 0xB94A3E80,
        0x188483918: 0x53107C10,
        0x18848391C: 0x121C0210,
        0x188483920: 0x2A100036,
        0x188483924: 0x7800D276,
        0x188485714: 0x52800029,
        0x188485718: 0x0A681129,
        0x18848571C: 0xD34C3108,
        0x188485728: 0x8B295149,
        0x18848572C: 0xF8687936,
    }
    for address, expected in instructions.items():
        actual = image.u32(image.offset(address, 4))
        if actual != expected:
            raise ValueError(f"unreviewed FP16 instruction at {address:#x}")
    table = [image.cfstring(image.pointer(0x1D5B48030 + index * 8))
             for index in range(4)]
    assert table == ["fixed_frag_lph_cph", "fixed_frag_lph_cpf", None,
                     "fixed_frag_lpf_cpf"]
    source = (here.parent / "userland/a5mali-metal/StockMetalPlugin/"
              "A5MaliMetalDevice.m").read_text()
    assert re.search(r"-\s*\(BOOL\)supportsNativeHardwareFP16\s*"
                     r"\{\s*return YES;\s*\}", source)
    assert re.search(r"-\s*\(BOOL\)supportsFamily:.*?return NO;", source)
    assert re.search(r"-\s*\(BOOL\)supportsFeatureSet:.*?return NO;", source)
    # Captured lpf_cpf fixes CPfloat=1. Toggling the one genuine capability
    # preserves that bit and selects the existing lph_cpf, never lph_cph.
    for native_fp16 in (False, True):
        flags = (int(native_fp16) | 0) << 20  # Apple1 remains false.
        fragment_spec = ((flags >> 16) & 0x10) | (1 << 12)
        row = 1 & ~(fragment_spec >> 4)
        index = row * 2 + ((fragment_spec >> 12) & 1)
        assert table[index] == ("fixed_frag_lph_cpf" if native_fp16
                                else "fixed_frag_lpf_cpf")
    print("stock UUID/opcodes/precision table: passed; native FP16 selects lph_cpf; Apple families remain false")


if __name__ == "__main__":
    main()
