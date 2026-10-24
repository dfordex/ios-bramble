#!/usr/bin/env python3
"""RAM contract checks; optionally replay private BOOT/loader inputs, never embed them."""
import argparse
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import adt
import mkadt
import mkpayload

spec = importlib.util.spec_from_file_location('metal_pack', HERE / 'a5xelte-pack-metal-boot.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


def loader():
    blob = bytearray(64)
    blob[56:60] = b'ARMd'
    struct.pack_into('<Q', blob, 8, 0x205000)
    return bytes(blob) + b'A5XRAM01' + struct.pack('<2Q', 0x80000000, 0xae000000)


def tree():
    root = mkadt.node('root', [('untouched', b'abc')])
    root.children.append(mkadt.node('chosen', [('dram-base', struct.pack('<Q', 0x80000000)),
                       ('dram-size', struct.pack('<Q', 512 << 20)), ('seed', b'private-seed')]))
    # Nonzero padding must survive; parse/serialize would erase it.
    blob = bytearray(adt.serialize(root))
    pos = blob.index(b'abc')
    blob[pos + 3] = 0xa5
    return bytes(blob)


class RamWindow(unittest.TestCase):
    def test_default_checkpoint_bytes_unchanged(self):
        blob = tree()
        self.assertEqual(pack.prepare_ram(blob, b'old-loader', 0x80000000, 512 << 20),
                         (blob, b'old-loader'))

    def test_only_existing_size_changes_and_payload_derives_it(self):
        before = tree()
        after, selected = pack.prepare_ram(before, b'old-loader', 0x80000000, 512 << 20, 736, loader())
        self.assertEqual(selected, loader())
        self.assertEqual(len(before), len(after))
        pos = before.index(b'dram-size'.ljust(32, b'\0')) + 36
        self.assertEqual(after[:pos], before[:pos])
        self.assertEqual(after[pos + 8:], before[pos + 8:])
        self.assertEqual(mkpayload.adt_dram(after), (0x80000000, 736 << 20))
        # Actual payload builder, with a minimal arm64 Mach-O (no private bytes).
        kernel = bytearray(4096)
        struct.pack_into('<8I', kernel, 0, 0xfeedfacf, 0x100000c, 0, 2, 2, 72 + 288, 0, 0)
        struct.pack_into('<II16s4Q4I', kernel, 32, 0x19, 72, b'__TEXT',
                         0xfffffff007004000, 4096, 0, 4096, 7, 5, 0, 0)
        struct.pack_into('<4I', kernel, 104, 5, 288, 6, 68)
        struct.pack_into('<Q', kernel, 104 + 16 + 32 * 8, 0xfffffff007004000)
        with tempfile.TemporaryDirectory() as tmp:
            kp, ap = Path(tmp) / 'kernel', Path(tmp) / 'adt'
            kp.write_bytes(kernel)
            ap.write_bytes(after)
            payload, _ = mkpayload.build(str(kp), str(ap), 'cpus=4')
        self.assertEqual(struct.unpack_from('<2Q', payload, 0x38), (0x80000000, 736 << 20))

    def test_rejects_incoherent_capacity_before_pack(self):
        cases = [(0x80000000, 512 << 20, 736, None),
                 (0x80000000, 736 << 20, 736, loader()),
                 (0x80000000, 512 << 20, 512, loader()),
                 (0x80000000, 512 << 20, 736, loader().replace(b'\xae', b'\xaf')),
                 (0x80000000, 512 << 20, 736, loader() + loader())]
        for base, size, mib, supplied in cases:
            with self.subTest(size=size, mib=mib, supplied=supplied):
                with self.assertRaises(ValueError):
                    pack.prepare_ram(tree(), b'old-loader', base, size, mib, supplied)

    def test_rejects_malformed_and_duplicate_identity(self):
        root, _ = adt.parse(tree())
        root.children.append(root.children[0])
        duplicate = adt.serialize(root)
        root.children.pop()
        root.children[0].props.append(('dram-size', 0, struct.pack('<Q', 512 << 20)))
        for blob in (tree()[:-1], tree() + b'junk', duplicate, adt.serialize(root)):
            with self.assertRaises(ValueError):
                pack.prepare_ram(blob, b'old-loader', 0x80000000, 512 << 20, 736, loader())

    def test_cli_incoherent_choices_reject_before_input_reads(self):
        for flags, reason in ((['--ram-mib', '736'], '--ram-mib 736 requires --loader-path'),
                              (['--loader-path', 'missing'], '--loader-path requires --ram-mib 736')):
            result = subprocess.run([sys.executable, str(HERE / 'a5xelte-pack-metal-boot.py'),
                'missing-ref', 'missing-kernel', 'missing-output', *flags], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn(reason, result.stderr)
            self.assertNotIn('FileNotFoundError', result.stderr)


def replay(reference, default_loader, extended_loader):
    boot = reference.read_bytes()
    ks, _, rs, _, _, _, _, page = struct.unpack_from('<8I', boot, 8)
    inherited = boot[page:page + ks]
    assert inherited == default_loader.read_bytes(), 'default loader differs from actual checkpoint'
    off = page + (ks + page - 1) // page * page
    payload = boot[off:off + rs]
    ao, az = struct.unpack_from('<2Q', payload, 0x20)
    original = payload[ao:ao + az]
    base, size = struct.unpack_from('<2Q', payload, 0x38)
    assert pack.prepare_ram(original, inherited, base, size) == (original, inherited)
    changed, _ = pack.prepare_ram(original, inherited, base, size, 736, extended_loader.read_bytes())
    assert mkpayload.adt_dram(changed) == (0x80000000, 736 << 20)
    pos = original.index(b'dram-size'.ljust(32, b'\0')) + 36
    assert changed[:pos] == original[:pos] and changed[pos + 8:] == original[pos + 8:]
    print('Private replay PASS: actual checkpoint loader exact; ADT differs only inside dram-size[8].')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference-boot', type=Path)
    parser.add_argument('--loader-512', type=Path)
    parser.add_argument('--loader-736', type=Path)
    args, rest = parser.parse_known_args()
    if any((args.reference_boot, args.loader_512, args.loader_736)):
        if not all((args.reference_boot, args.loader_512, args.loader_736)):
            parser.error('all three private replay inputs are required')
        replay(args.reference_boot, args.loader_512, args.loader_736)
    unittest.main(argv=[sys.argv[0], *rest])
