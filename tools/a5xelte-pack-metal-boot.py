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


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('reference_boot', type=Path)
    ap.add_argument('kernel', type=Path, help='fresh linked unstripped arm64 kernel')
    ap.add_argument('output_boot', type=Path)
    ap.add_argument('--install-bundle', action='store_true',
                    help='install the locally embedded bundle through the mounted HFS VFS')
    ap.add_argument('--test-downsample', action='store_true',
                    help='run the actual translated downsample4 shaders once on private GPU memory')
    ap.add_argument('--compiler', action='store_true',
                    help='enable signed on-device compiler helpers embedded by patches0172/0173')
    ap.add_argument('--test-shader-suite', action='store_true',
                    help='run the locally embedded Mac shader GPU fixture suite')
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
    if args.test_shader_suite:
        if b'A5XELTE G3D SUITE: completed passed=' not in args.kernel.read_bytes():
            ap.error('kernel lacks the generated Mac shader suite')
        required['a5shadersuite'] = '1'
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
        required['a5downsampletest'] = '1'
    if args.install_bundle:
        if b'A5XELTE Metal install:' not in args.kernel.read_bytes():
            ap.error('kernel lacks the embedded bundle installer')
        required.update(a5metal_install='1', rootrw='1', emmcwrite='1',
                        emmcroot='USERDATA',
                        sweetnull='backboardd,a5mali-metal-probe')
    if args.compiler:
        if not args.install_bundle:
            ap.error('--compiler requires --install-bundle')
        if b'/usr/libexec/a5shader-compile' not in args.kernel.read_bytes():
            ap.error('kernel lacks the native compiler installation/authorization')
        required.update(a5compiler='1',
                        sweetnull='backboardd,a5mali-metal-probe,a5shader-compile')
    words = [w for w in words if w.split('=', 1)[0] not in required]
    words += [f'{k}={v}' for k, v in required.items()]
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
