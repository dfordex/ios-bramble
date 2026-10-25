#!/usr/bin/env python3
"""Check identity consistency without changing Samsung hardware properties."""
import copy
from pathlib import Path
import subprocess
import unittest

import adt
import a5xelte_identity as identity
import mkadt
import mkadt_a5xelte


class Identity(unittest.TestCase):
    def test_fresh_tree_and_repacked_tree_share_identity(self):
        root = mkadt_a5xelte.build()
        before = copy.deepcopy(root)
        # Reproduce the old active BOOT's mixed donor/Samsung identity.
        mkadt_a5xelte.set_prop(root, 'model', b'iPhone10,3\0')
        mkadt_a5xelte.set_prop(root, 'compatible', b'samsung,a5xelte\0samsung,exynos7580\0AppleARM\0')
        mkadt_a5xelte.set_prop(root, 'target-type', b'D22\0')
        mkadt_a5xelte.set_prop(root, 'target-sub-type', b'D22AP\0')
        result = identity.rewrite(adt.serialize(root))
        self.assertEqual(result, adt.serialize(before))
        self.assertEqual(identity.rewrite(result), result)
        parsed, end = adt.parse(result)
        self.assertEqual(end, len(result))
        self.assertEqual(parsed.prop('model'), b'iPhone10,5\0')
        self.assertEqual(parsed.prop('compatible').split(b'\0')[0], b'D211AP')
        self.assertEqual(parsed.prop('target-type'), b'D211\0')
        self.assertEqual(parsed.prop('target-sub-type'), b'D211AP\0')
        # Child hardware descriptions, topology, memory and input stay exact.
        self.assertEqual([adt.serialize(n) for n in parsed.children],
                         [adt.serialize(n) for n in before.children])

    def test_foreign_tree_and_duplicate_identity_rejected(self):
        root = mkadt.node('device-tree', [('compatible', b'xiaomi,sweet\0')])
        with self.assertRaises(ValueError):
            identity.rewrite(adt.serialize(root))
        root = mkadt_a5xelte.build()
        root.props.append(('model', 0, b'iPad8,6\0'))
        with self.assertRaises(ValueError):
            identity.rewrite(adt.serialize(root))

    def test_real_kernel_sysctl_branch_for_both_caller_platforms(self):
        # Exercise the actual patched guard; A5 processes must always take
        # PEGetMachineName/PEGetModelName, never the macOS iPad/arm64 branch.
        patch = (Path(__file__).resolve().parents[1] / 'xnu/patches/'
                 '0214-a5xelte-consistent-ios-identity.patch').read_text()
        guard = next(line[1:] for line in patch.splitlines() if line.startswith('+#if '))
        for board, expected in (('A5XELTE', 'TREE'), ('SWEET', 'TREE'), ('OTHER', 'MAC')):
            source = guard + '\nMAC\n#else\nTREE\n#endif\n'
            result = subprocess.run(['cc', '-E', '-P', '-x', 'c',
                '-DXNU_TARGET_OS_OSX=1', '-D__arm64__=1',
                '-DARM64_BOARD_CONFIG_' + board, '-'], input=source,
                text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout.strip(), expected)


if __name__ == '__main__':
    unittest.main()
