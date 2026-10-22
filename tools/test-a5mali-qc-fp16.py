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
    # get_pipeline_spec moves bit20 into FragmentShader::Spec bit4, then
    # uses it again to choose forced CP-float versus an initialized config.
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
        0x188483A70: 0x35000070,
        0x188483A74: 0x52820008,
        0x188483A78: 0x14000008,
        0x188483A7C: 0x902CCBA8,
        0x188483A80: 0xF9409908,
        0x188483A84: 0xB100051F,
        0x188483A88: 0x54000F81,
        0x188483A8C: 0x902CCBA8,
        0x188483A90: 0x39446108,
        0x188483A94: 0x53144D08,
        0x188483A98: 0x2A160309,
        0x188483A9C: 0x2A0902E9,
        0x188483AA0: 0x2A090329,
        0x188483AA4: 0x2A1A0129,
        0x188483AA8: 0x2A1B0129,
        0x188483AAC: 0x2A090389,
        0x188483AB0: 0x2A090108,
        0x188483AB4: 0x79443A89,
        0x188483AB8: 0x53144D29,
        0x188483ABC: 0x1213012A,
        0x188483AC0: 0x2A080148,
        0x188483AC4: 0x12120129,
        0x188483AC8: 0x2A090108,
        0x188483ACC: 0x7800D268,
        0x188483C78: 0x902CCBA0,
        0x188483C7C: 0x9104C000,
        0x188483C80: 0xD026B621,
        0x188483C84: 0x91072021,
        0x188483C88: 0x940339F1,
        0x188483C8C: 0x17FFFF80,
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
    # Model both arms of the actual later branch, with Apple1 false.
    # Without native FP16, a74 forces CPfloat=1. With it, a90 loads the
    # initialized configuration byte; test its two precision values rather
    # than incorrectly preserving the earlier capture's CPfloat bit.
    expected_names = {
        (False, 0): "fixed_frag_lpf_cpf",
        (False, 1): "fixed_frag_lpf_cpf",
        (True, 0): "fixed_frag_lph_cph",  # Observed on phone in 0186.
        (True, 1): "fixed_frag_lph_cpf",
    }
    for native_fp16 in (False, True):
        for precision_config in (0, 1):
            flags = (int(native_fp16) | 0) << 20
            native_half_bit = (flags >> 16) & 0x10
            cp_float = precision_config if native_half_bit else 1
            fragment_spec = native_half_bit | (cp_float << 12)
            row = 1 & ~(fragment_spec >> 4)
            index = row * 2 + ((fragment_spec >> 12) & 1)
            assert table[index] == expected_names[native_fp16, precision_config]
    print("stock UUID/opcodes/precision table: passed; four FP16/config branches passed; "
          "config0 selects observed lph_cph, config1 selects lph_cpf; Apple families remain false")


if __name__ == "__main__":
    main()
