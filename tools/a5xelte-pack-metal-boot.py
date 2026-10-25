#!/usr/bin/env python3
"""Prepare an opt-in discovery BOOT using a known-working Samsung XNU BOOT.

Reuses its loader and hardware ADT, normalizes the A5 iOS identity and replaces
the XNU payload. Does not flash or install
the separately built Metal bundle. All binary inputs/outputs stay private.
"""
import argparse
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

import mkpayload
import a5xelte_identity


def argument_parser():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('reference_boot', type=Path)
    ap.add_argument('kernel', type=Path, help='fresh linked unstripped arm64 kernel')
    ap.add_argument('output_boot', type=Path)
    ap.add_argument('--ram-mib', type=int, choices=(512, 736), default=512,
                    help='managed RAM window; 736 is an opt-in physically unverified lab extension')
    ap.add_argument('--loader-path', type=Path,
                    help='explicit 736 MiB loader built with RAM_MIB=736; requires --ram-mib 736')
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
                    help='restore the explicitly selected embedded UI or stock app set through HFS VFS')
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


def prepare_ram(adt_blob, reference_loader, payload_base, payload_size,
                ram_mib=512, loader_blob=None):
    """Patch only the existing /chosen/dram-size value, retaining raw ADT bytes.

    SM-A510F Ax hardware captures and recovered memreserve declarations bound
    this opt-in 0x80000000..0xae000000 window. Runtime validation is still needed;
    this is not a universal Samsung/Android memory layout.
    """
    blob = bytearray(adt_blob)
    chosen_props = []

    def walk(off, depth):
        if depth > 64 or off + 8 > len(blob):
            raise ValueError('malformed ADT node')
        nprops, nchildren = struct.unpack_from('<II', blob, off)
        off += 8
        props = {}
        name = None
        for _ in range(nprops):
            if off + 36 > len(blob):
                raise ValueError('truncated ADT property')
            key = bytes(blob[off:off + 32]).split(b'\0', 1)[0]
            size = struct.unpack_from('<I', blob, off + 32)[0] & 0x7fffffff
            value = off + 36
            end = value + ((size + 3) & ~3)
            if end > len(blob) or key in props:
                raise ValueError('invalid or duplicate ADT property')
            props[key] = (value, size)
            if key == b'name':
                name = bytes(blob[value:value + size]).split(b'\0', 1)[0]
            off = end
        if depth == 1 and name == b'chosen':
            chosen_props.append(props)
        for _ in range(nchildren):
            off = walk(off, depth + 1)
        return off

    if walk(0, 0) != len(blob) or len(chosen_props) != 1:
        raise ValueError('ADT must contain exactly one complete /chosen')
    props = chosen_props[0]
    fields = []
    for key in (b'dram-base', b'dram-size'):
        if key not in props or props[key][1] != 8:
            raise ValueError('ADT lacks a unique 64-bit /chosen/' + key.decode())
        fields.append(struct.unpack_from('<Q', blob, props[key][0])[0])
    base, size = fields
    if base != 0x80000000 or size not in (512 << 20, 736 << 20):
        raise ValueError('unsupported reference managed RAM window')
    if (base, size) != (payload_base, payload_size):
        raise ValueError('reference payload and ADT RAM disagree')
    if ram_mib not in (512, 736):
        raise ValueError('unsupported managed RAM size')
    if ram_mib == 512:
        if loader_blob is not None or size != 512 << 20 or b'A5XRAM01' in reference_loader:
            raise ValueError('512 MiB checkpoint requires its inherited 512 MiB loader/ADT')
        return bytes(blob), reference_loader
    if loader_blob is None:
        raise ValueError('--ram-mib 736 requires --loader-path built with RAM_MIB=736')
    contract = b'A5XRAM01' + struct.pack('<2Q', base, 0xae000000)
    if (loader_blob.count(b'A5XRAM01') != 1 or contract not in loader_blob or
            len(loader_blob) < 64 or loader_blob[56:60] != b'ARMd' or
            struct.unpack_from('<Q', loader_blob, 8)[0] != 0x205000 or
            struct.unpack_from('<Q', loader_blob, 16)[0] != 0):
        raise ValueError('loader lacks the exact 736 MiB Samsung capacity contract')
    struct.pack_into('<Q', blob, props[b'dram-size'][0], 736 << 20)
    return bytes(blob), loader_blob


def main():
    ap = argument_parser()
    args = ap.parse_args()
    if args.loader_path is not None and args.ram_mib != 736:
        ap.error('--loader-path requires --ram-mib 736')
    if args.ram_mib == 736 and args.loader_path is None:
        ap.error('--ram-mib 736 requires --loader-path')
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
    try:
        adt_blob, loader_blob = prepare_ram(
            payload[adt_off:adt_off + adt_size], ref[page:page + ks],
            *struct.unpack_from('<2Q', payload, 0x38), args.ram_mib,
            args.loader_path.read_bytes() if args.loader_path else None)
        adt_blob = a5xelte_identity.rewrite(adt_blob)
    except (ValueError, OSError, struct.error) as exc:
        ap.error(str(exc))
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
        app_kernel = args.kernel.read_bytes()
        app_payload = b'/Applications/PosterBoard.app/PosterBoard' in app_kernel or all(
            marker in app_kernel for marker in (
                b'/Applications/Preferences.app/Preferences',
                b'/Applications/MobileTimer.app/MobileTimer',
                b'/Applications/MobileSafari.app/MobileSafari'))
        if not app_payload or not all(marker in app_kernel for marker in (
                b'a5apps_install', b'A5XELTE Apps install: display bundles installed')):
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
        adt.write_bytes(adt_blob)
        loader = tmp / 'Image'
        loader.write_bytes(loader_blob)
        new_payload, info = mkpayload.build(str(args.kernel), str(adt), cmdline)
        if struct.unpack_from('<2Q', new_payload, 0x38) != (0x80000000, args.ram_mib << 20):
            ap.error('generated payload RAM does not match the selected loader/ADT')
        payload_path = tmp / 'xnu.payload'
        payload_path.write_bytes(new_payload)
        subprocess.run([sys.executable, str(Path(__file__).with_name('a5xelte-pack-probe.py')),
                        str(args.reference_boot), str(loader), str(args.output_boot),
                        '--ramdisk', str(payload_path)], check=True)
    print(f'kernel entry={info["entry"]}; chained fixups={info["fixups"]}')
    print(f'boot arguments: {cmdline}')
    print(f'managed RAM: {args.ram_mib} MiB at 0x80000000')
    print(f'iOS identity: {a5xelte_identity.PRODUCT_TYPE} / {a5xelte_identity.BOARD_TYPE}')
    if args.ram_mib == 736:
        print('736 MiB is physically unverified: verify XNU memory/page counts and sustained allocation on device.')
    print('Companion: /System/Library/Extensions/A5MaliMetal.bundle (' +
          ('installed from embedded payload before launchd' if args.install_bundle
           else 'separate installation required') + ').')
    print('Candidate prepared; verify its stock Metal acceptance and rendering on the device.')


if __name__ == '__main__':
    main()
