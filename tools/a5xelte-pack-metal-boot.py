#!/usr/bin/env python3
"""Prepare an opt-in discovery BOOT using a known-working Samsung XNU BOOT.

Reuses its loader and ADT; replaces the XNU payload. Does not flash or install
the separately built Metal bundle. All binary inputs/outputs stay private.
"""
import argparse
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

import mkpayload


def argument_parser():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('reference_boot', type=Path)
    ap.add_argument('kernel', type=Path, help='fresh linked unstripped arm64 kernel')
    ap.add_argument('output_boot', type=Path)
    ap.add_argument('--install-bundle', action='store_true',
                    help='install the locally embedded bundle through the mounted HFS VFS')
    downsample = ap.add_mutually_exclusive_group()
    downsample.add_argument('--test-downsample', action='store_true',
                    help='run the actual translated downsample4 shaders once on private GPU memory')
    downsample.add_argument('--skip-downsample', action='store_true',
                    help='write a5downsampletest=0, replacing any inherited test setting')
    ap.add_argument('--compiler', action='store_true',
                    help='enable signed on-device compiler helpers embedded by patches0172/0173')
    suite = ap.add_mutually_exclusive_group()
    suite.add_argument('--test-shader-suite', action='store_true',
                    help='run the locally embedded Mac shader GPU fixture suite')
    suite.add_argument('--skip-shader-suite', action='store_true',
                    help='write a5shadersuite=0, replacing any inherited test setting')
    ap.add_argument('--native-rendering', action='store_true',
                    help='enable the privileged local Metal native queue; requires a compiled registry bundle')
    ap.add_argument('--restore-display-apps', action='store_true',
                    help='restore the exact six embedded display UI bundles through HFS VFS')
    ap.add_argument('--ui-diagnostics', action='store_true',
                    help='enable bounded UI thread samples and independent exception-output budgets')
    ap.add_argument('--storage-multiblock', action='store_true',
                    help='enable bounded 32-sector eMMC read/write batches')
    ap.add_argument('--touch-input', action='store_true',
                    help='enable touch controller/polling independently of quiet contact logging')
    return ap


def selftest_boot_arguments(args):
    """Only explicit test/skip choices override inherited optional test gates."""
    required = {}
    for key, test, skip in (
            ('a5shadersuite', args.test_shader_suite, args.skip_shader_suite),
            ('a5downsampletest', args.test_downsample, args.skip_downsample)):
        if test or skip:
            required[key] = '1' if test else '0'
    return required


def rewrite_boot_arguments(words, required):
    # Remove every inherited occurrence: PE_parse_boot_argn must not find an
    # older =1 before the explicit =0. Unrelated/native settings are retained.
    return ([word for word in words if word.split('=', 1)[0] not in required] +
            [f'{key}={value}' for key, value in required.items()])


def main():
    ap = argument_parser()
    args = ap.parse_args()
    if args.output_boot.exists():
        ap.error('output exists; choose a new private output path')
    ref = args.reference_boot.read_bytes()
    if ref[:8] != b'ANDROID!' or len(ref) < 2048:
        ap.error('not a Samsung Android BOOT')
    ks, _, rs, _, ss, _, _, page, _, _ = struct.unpack_from('<10I', ref, 8)
    if page != 2048 or ss:
        ap.error('unsupported BOOT layout')
    roff = page + (ks + page - 1) // page * page
    payload = ref[roff:roff + rs]
    if len(payload) != rs or payload[:8] != b'SWEETXNU' or len(payload) < 680:
        ap.error('reference lacks a complete XNU payload')
    if struct.unpack_from('<I', payload, 8)[0] != 1:
        ap.error('unsupported XNU payload version')
    adt_off, adt_size = struct.unpack_from('<2Q', payload, 0x20)
    if not adt_size or adt_off + adt_size > len(payload):
        ap.error('reference ADT is truncated')
    words = payload[0x48:0x2a8].split(b'\0', 1)[0].decode('ascii').split()
    required = {'a5gpu': '8', 'a5gpuclient': '1', 'a5metal': '1'}
    required.update(selftest_boot_arguments(args))
    if args.native_rendering:
        if not args.install_bundle:
            ap.error('--native-rendering requires --install-bundle')
        if b'A5XELTE G3D native: profile=' not in args.kernel.read_bytes():
            ap.error('kernel lacks the native terminal-fence queue')
        required['a5native'] = '1'
    if args.test_shader_suite:
        if b'A5XELTE G3D SUITE: completed passed=' not in args.kernel.read_bytes():
            ap.error('kernel lacks the generated Mac shader suite')
    if args.test_downsample:
        if b'actual QuartzCore downsample_blur_vert_lph/downsample_4_frag_lph start' not in args.kernel.read_bytes():
            ap.error('kernel lacks the actual translated downsample4 fixture/test')
        if b'A5XELTE G3D DS4: AS0 LOCK/FLUSH_PT complete' not in args.kernel.read_bytes():
            ap.error('kernel lacks the corrected downsample4 page-table flush')
        if b'A5XELTE G3D DS4 diag: row=' not in args.kernel.read_bytes():
            ap.error('kernel lacks the downsample4 geometry/pixel diagnostics')
        for marker in (b'A5XELTE G3D: T720 shader config old=',
                       b'A5XELTE G3D: full-panel tile bounds=0..67,0..119;'):
            if marker not in args.kernel.read_bytes():
                ap.error('kernel lacks the released T720 initialization/panel-bounds corrections')
    if args.install_bundle:
        if b'A5XELTE Metal install:' not in args.kernel.read_bytes():
            ap.error('kernel lacks the embedded bundle installer')
        required.update(a5metal_install='1', rootrw='1', emmcwrite='1',
                        emmcroot='USERDATA',
                        sweetnull='backboardd,a5mali-metal-probe')
    if args.restore_display_apps:
        if not args.install_bundle:
            ap.error('--restore-display-apps requires --install-bundle')
        if not all(marker in args.kernel.read_bytes() for marker in (
                b'a5apps_install', b'A5XELTE Apps install: display bundles installed',
                b'/Applications/PosterBoard.app/PosterBoard')):
            ap.error('kernel lacks the gated display-app installer')
        required['a5apps_install'] = '1'
    if args.compiler:
        if not args.install_bundle:
            ap.error('--compiler requires --install-bundle')
        if b'/usr/libexec/a5shader-compile' not in args.kernel.read_bytes():
            ap.error('kernel lacks the native compiler installation/authorization')
        required.update(a5compiler='1',
                        sweetnull='backboardd,a5mali-metal-probe,a5shader-compile')
    if args.ui_diagnostics:
        if not all(marker in args.kernel.read_bytes() for marker in (
                b'A5XELTE UI diag: sampler enabled;', b'SBT %s tid=',
                b'server_threads=16 split_stack=1')):
            ap.error('kernel lacks the bounded split-stack UI/server diagnostics')
        required['a5uidiag'] = '1'
    if args.storage_multiblock:
        if b'A5XELTE eMMC: bounded CMD23/CMD18/CMD25 blocks=' not in args.kernel.read_bytes():
            ap.error('kernel lacks bounded eMMC multi-block transfers')
        required['a5emmc_blocks'] = '32'
    if args.touch_input:
        if b'A5XELTE TOUCH: enabled=%d contact_log=%d' not in args.kernel.read_bytes():
            ap.error('kernel lacks touch enable independent of contact logging')
        required.update(a5touch='1', a5touchlog='0')
    words = rewrite_boot_arguments(words, required)
    cmdline = ' '.join(words)
    if len(cmdline.encode()) >= mkpayload.BOOT_LINE_LENGTH:
        ap.error('boot arguments would be truncated')
    kernel = args.kernel.read_bytes()
    if b'opt-in stock Metal discovery proxy registered' not in kernel:
        ap.error('kernel does not contain the enabled discovery path')
    macho = mkpayload.parse_macho(kernel)
    if macho['cputype'] != 0x100000c or macho['cpusub'] != 0:
        ap.error('kernel must be plain arm64, not arm64e')
    with tempfile.TemporaryDirectory(prefix='a5-metal-pack-') as tmp:
        tmp = Path(tmp)
        adt = tmp / 'board.adt'
        adt.write_bytes(payload[adt_off:adt_off + adt_size])
        loader = tmp / 'Image'
        loader.write_bytes(ref[page:page + ks])
        new_payload, info = mkpayload.build(str(args.kernel), str(adt), cmdline)
        payload_path = tmp / 'xnu.payload'
        payload_path.write_bytes(new_payload)
        subprocess.run([sys.executable, str(Path(__file__).with_name('a5xelte-pack-probe.py')),
                        str(args.reference_boot), str(loader), str(args.output_boot),
                        '--ramdisk', str(payload_path)], check=True)
    print(f'kernel entry={info["entry"]}; chained fixups={info["fixups"]}')
    print(f'boot arguments: {cmdline}')
    print('Companion: /System/Library/Extensions/A5MaliMetal.bundle (' +
          ('installed from embedded payload before launchd' if args.install_bundle
           else 'separate installation required') + ').')
    print('Candidate prepared; verify its stock Metal acceptance and rendering on the device.')


if __name__ == '__main__':
    main()
