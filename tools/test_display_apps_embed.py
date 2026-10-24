#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Synthetic source-only tests; no Apple binaries, device or filesystem images."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

SPEC = importlib.util.spec_from_file_location('embed', Path(__file__).with_name('a5xelte-metal-bundle-embed.py'))
embed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(embed)


class DisplayAppsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.apps = self.root / 'Applications'
        self.apps.mkdir()
        for name in embed.DISPLAY_APPS + embed.STOCK_APPS:
            app = self.apps / name
            (app / '_CodeSignature').mkdir(parents=True)
            (app / 'executable').write_bytes(bytes(range(256)) * 16)
            (app / 'executable').chmod(0o751)
            (app / '_CodeSignature' / 'CodeResources').write_bytes(b'signature unchanged')
        # Not an allowlisted bundle: must never appear in payload.
        (self.apps / 'Unrelated.app').mkdir()
        (self.apps / 'Unrelated.app' / 'private').write_bytes(b'not requested')

    def tearDown(self):
        self.temp.cleanup()

    def test_real_metadata_and_exact_roots(self):
        files, dirs, attrs = embed.display_app_entries(self.apps)
        self.assertEqual(len(files), 12)
        self.assertEqual(len(dirs), 13)
        self.assertEqual(dirs[0][0], '/Applications')
        self.assertFalse(attrs['functionalXattrsOmitted'])
        for path, data, mode, uid, gid in files:
            original = self.apps / path.removeprefix('/Applications/')
            self.assertEqual(data, original.read_bytes())
            self.assertEqual((mode, uid, gid), (original.stat().st_mode & 0o7777, original.stat().st_uid, original.stat().st_gid))
        self.assertTrue(all('Unrelated' not in row[0] for row in files + dirs))

    def test_stock_apps_are_an_independent_exact_set(self):
        files, dirs, _ = embed.display_app_entries(self.apps, embed.STOCK_APPS)
        self.assertEqual(len(files), 6)
        self.assertEqual(len(dirs), 7)
        roots = {row[0].split('/')[2] for row in files}
        self.assertEqual(roots, set(embed.STOCK_APPS))
        self.assertFalse(roots.intersection(embed.DISPLAY_APPS))
        for path, data, mode, uid, gid in files:
            source = self.apps / path.removeprefix('/Applications/')
            self.assertEqual(data, source.read_bytes())
            self.assertEqual((mode, uid, gid),
                (source.stat().st_mode & 0o7777, source.stat().st_uid, source.stat().st_gid))
        with self.assertRaisesRegex(ValueError, 'approved app sets'):
            embed.display_app_entries(self.apps, ('Unrelated.app',))
        (self.apps / embed.STOCK_APPS[0] / 'link').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'no links'):
            embed.display_app_entries(self.apps, embed.STOCK_APPS)

    def test_stock_clock_exact_restore_source(self):
        staged = self.root / 'private/var/staged_system_apps/MobileTimer.app'
        staged.parent.mkdir(parents=True)
        (self.apps / 'MobileTimer.app').rename(staged)
        files, _, _ = embed.display_app_entries(self.apps, embed.STOCK_APPS)
        timer = [row for row in files if row[0].startswith('/Applications/MobileTimer.app/')]
        self.assertEqual(len(timer), 2)
        for path, data, mode, uid, gid in timer:
            original = staged / path.removeprefix('/Applications/MobileTimer.app/')
            self.assertEqual(data, original.read_bytes())
            self.assertEqual((mode, uid, gid),
                (original.stat().st_mode & 0o7777, original.stat().st_uid, original.stat().st_gid))

    def test_missing_bundle_and_symlink_rejected(self):
        app = self.apps / embed.DISPLAY_APPS[0]
        (app / 'link').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'no links'):
            embed.display_app_entries(self.apps)
        (app / 'link').unlink()
        app.rename(self.apps / 'missing.app')
        with self.assertRaisesRegex(ValueError, 'required display bundle'):
            embed.display_app_entries(self.apps)

    def test_unknown_functional_xattr_rejected(self):
        with patch.object(embed, 'xattr_names', return_value=['com.apple.ResourceFork']):
            with self.assertRaisesRegex(ValueError, 'functional/unknown xattr'):
                embed.display_app_entries(self.apps)
        with patch.object(embed, 'xattr_names', return_value=['com.apple.decmpfs']):
            _, _, attrs = embed.display_app_entries(self.apps)
            self.assertGreater(attrs['omittedStorageOrProvenance']['com.apple.decmpfs'], 0)

    def test_empty_utf8_and_size_bound(self):
        app = self.apps / embed.DISPLAY_APPS[0]
        (app / 'ş😄"\\.txt').write_bytes(b'')
        files, _, _ = embed.display_app_entries(self.apps)
        empty = next(e for e in files if e[0].endswith('.txt'))
        self.assertEqual(empty[1], b'')
        escaped = embed.c_string(empty[0])
        self.assertTrue(escaped.isascii())
        self.assertIn('\\042', escaped)
        self.assertIn('\\134', escaped)
        with (app / 'oversize').open('wb') as stream:
            stream.truncate(embed.MAX_APP_FILE + 1)
        with self.assertRaisesRegex(ValueError, '32MiB'):
            embed.display_app_entries(self.apps)

    def test_generated_existing_assets_empty_sentinel_and_compression(self):
        bundle = self.root / 'A5MaliMetal.bundle'
        (bundle / '_CodeSignature').mkdir(parents=True)
        macho = struct.pack('<II', 0xFEEDFACF, 0x0100000C) + bytes(24)
        (bundle / 'A5MaliMetal').write_bytes(macho)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'A5MaliMetal','NSPrincipalClass':'A5MaliMetalDevice'}))
        (bundle / '_CodeSignature' / 'CodeResources').write_bytes(b'codesig')
        (self.apps / embed.DISPLAY_APPS[0] / 'zero').write_bytes(b'')
        out = self.root / 'payload.inc'
        stdout = io.StringIO()
        with patch.object(sys, 'argv', ['embed', str(bundle), str(out), '--display-apps', str(self.apps)]), contextlib.redirect_stdout(stdout):
            embed.main()
        receipt = json.loads(stdout.getvalue())
        self.assertEqual(len(receipt['files']), 16)
        text = out.read_text()
        self.assertIn('A5METAL_DIRECTORIES_PRESENT 1', text)
        self.assertIn('nonnull sentinel for a zero-byte regular file', text)
        arrays = re.findall(r'static const unsigned char a5metal_payload_\d+\[\] = \{(.*?)\};', text, re.S)
        rows = re.findall(r'\{ "([^"]+)", a5metal_payload_(\d+), (\d+)U, 0[0-7]+, (\d+)U, \d+U, \d+U \}', text)
        self.assertEqual(len(rows), len(receipt['files']))
        for path, index, length, packed in rows:
            data = bytes(int(x,16) for x in re.findall(r'0x([0-9a-f]{2})', arrays[int(index)]))
            restored = zlib.decompress(data) if int(packed) else data[:int(length)]
            self.assertEqual(len(restored), int(length))
            source = self.apps / path.removeprefix('/Applications/') if path.startswith('/Applications/') else bundle / path.removeprefix(embed.BUNDLE_DEST + '/')
            self.assertEqual(restored, source.read_bytes())


if __name__ == '__main__':
    unittest.main()
