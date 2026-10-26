#!/usr/bin/env python3
"""Build an entry-stage SM-A720F (a7y17lte, Exynos7880) ADT.

Adapted from mkadt_a5xelte.py. Addresses come from the phone's live device
tree read in TWRP. The XNU patches still hard-code some Exynos7580 registers
(buttons, touch, PMIC, display power, G3D); this ADT does not fix those, and
it omits the G3D node until the Mali-T830 is mapped.
"""
import argparse
import os
from pathlib import Path

import adt
import mkadt
import a5xelte_identity


# Must match shim/a720f/board.h A7_RAM_BASE/A7_RAM_END.
DRAM_BASE = 0x84000000
DRAM_SIZE = 0x3c000000


def set_prop(node, name, value):
    for i, (key, flags, _) in enumerate(node.props):
        if key == name:
            node.props[i] = (key, flags, value)
            return
    node.props.append((name, 0, value))


def child(node, name):
    for candidate in node.children:
        if candidate.prop('name') == mkadt.cstr(name):
            return candidate
    raise ValueError(f'missing donor ADT node {name}')


def build():
    # The donor's optional /product is D22AP-specific Apple metadata.
    root = mkadt.build(seed=os.urandom(64), qemu=True, donor_product=False)
    # Root compatible comes from a5xelte_identity.apply(): the kernel's
    # SweetPlatformExpert matches 'samsung,a5xelte', so the A7 keeps that name.
    chosen = child(root, 'chosen')
    buttons = child(root, 'buttons')
    # gpio_keys KEY_HOME on GPA1-7 is the iOS Home (Menu) button.
    set_prop(buttons, 'home-button-type', mkadt.u32(0))
    set_prop(buttons, 'button-names', b''.join(mkadt.cstr(name) for name in
                                       ('volup', 'voldown', 'hold', 'home')))
    set_prop(chosen, 'dram-base', mkadt.u64(DRAM_BASE))
    set_prop(chosen, 'dram-size', mkadt.u64(DRAM_SIZE))
    set_prop(chosen, 'firmware-version', mkadt.cstr('a720f-entry'))
    set_prop(chosen, 'system-firmware-version', mkadt.cstr('a720f-entry'))
    cpus = child(root, 'cpus')
    cpu0 = child(cpus, 'cpu0')
    set_prop(cpu0, 'compatible', mkadt.cstr('arm,cortex-a53') + mkadt.cstr('ARM,v8'))
    set_prop(cpu0, 'reg', mkadt.u32(0))
    set_prop(cpu0, 'timebase-frequency', mkadt.u32(26000000))
    # Live DT: cpu@0..3 and cpu@100..103, PSCI over smc, 26 MHz arch timer.
    for logical in range(1, 8):
        cluster, core = divmod(logical, 4)
        mpidr = (cluster << 8) | core
        cpus.children.append(mkadt.node(f'cpu{logical}', [
            ('device_type', mkadt.cstr('cpu')),
            ('compatible', mkadt.cstr('arm,cortex-a53') + mkadt.cstr('ARM,v8')),
            ('reg', mkadt.u32(mpidr)),
            ('cpu-id', mkadt.u32(logical)),
            ('cluster-id', mkadt.u32(cluster)),
            ('cluster-type', mkadt.u32(0)),
            ('die-cluster-id', mkadt.u32(cluster)),
            ('cluster-core-id', mkadt.u32(core)),
            ('l2-cache-id', mkadt.u32(cluster)),
            ('l3-cache-id', mkadt.u32(0)),
            ('state', mkadt.cstr('stopped')),
            ('timebase-frequency', mkadt.u32(26000000)),
            ('clock-frequency', mkadt.u32(1600000000)),
            ('bus-frequency', mkadt.u32(100000000)),
            ('memory-frequency', mkadt.u32(1866000000)),
            ('peripheral-frequency', mkadt.u32(26000000)),
            ('fixed-frequency', mkadt.u32(26000000)),
        ]))
    arm_io = child(root, 'arm-io')
    set_prop(arm_io, 'device_type', mkadt.cstr('a5xelte-io'))
    set_prop(arm_io, 'compatible', mkadt.cstr('samsung,exynos7880-io') +
             mkadt.cstr('arm-io'))
    set_prop(arm_io, 'ranges', mkadt.u64(0, 0x10000000, 0xf0000000))
    arm_io.children = [n for n in arm_io.children if n.prop('name') == mkadt.cstr('wdt')]
    # interrupt-controller@106E1000: GIC-400 distributor and CPU interface.
    # Virtual timer is PPI 11 (INTID 27) in the live /timer node.
    arm_io.children.append(mkadt.node('gic', [
        ('compatible', mkadt.cstr('arm,cortex-a15-gic')),
        ('interrupt-controller', mkadt.cstr('master')),
        ('virtual-timer-intid', mkadt.u32(27)),
        ('reg', mkadt.u64(0x06e1000, 0x1000, 0x06e2000, 0x1000)),
    ]))
    # S-Boot leaves the panel scanning out s3cfb.bootloaderfb = 0x67000000.
    arm_io.children.append(mkadt.node('disp0', [
        ('device_type', mkadt.cstr('display-subsystem')),
        ('compatible', mkadt.cstr('samsung,a5xelte-display')),
        ('canvas-width', mkadt.u32(1080)),
        ('canvas-height', mkadt.u32(1920)),
    ]))
    root.children = [n for n in root.children if n.prop('name') not in
                     (mkadt.cstr('sweet-fbcon'), mkadt.cstr('sweet-ufs'))]
    # The XNU patches look these nodes up by their a5xelte names.
    root.children.append(mkadt.node('a5xelte-fbcon', [
        ('reg', mkadt.u64(0x67000000, 1080 * 1920 * 4)),
        ('width', mkadt.u32(1080)),
        ('height', mkadt.u32(1920)),
        ('stride', mkadt.u32(4320)),
    ]))
    # dwmmc0@13540000, same window as on the Exynos7580.
    root.children.append(mkadt.node('a5xelte-emmc', [
        ('reg', mkadt.u64(0x13540000, 0x2000)),
    ]))
    return a5xelte_identity.apply(root)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    blob = adt.serialize(build())
    args.output.write_bytes(blob)
    print(f'{args.output}: {len(blob)} bytes')
