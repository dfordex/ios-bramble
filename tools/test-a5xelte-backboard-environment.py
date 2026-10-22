#!/usr/bin/env python3
"""Check the scoped backboardd launch-cache option without Apple inputs."""
import copy
import importlib.util
from pathlib import Path
import plistlib
import unittest

spec = importlib.util.spec_from_file_location('embed', Path(__file__).with_name('a5xelte-metal-bundle-embed.py'))
embed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(embed)


class BackboardEnvironment(unittest.TestCase):
    def setUp(self):
        self.original = {'VersionNumber': 7, 'AppExtensions': {'kept': b'unchanged'},
                         'LaunchDaemons': {embed.BACKBOARD_PLIST_DEST: {
                             'Label': 'com.apple.backboardd', 'ProgramArguments': ['/usr/libexec/backboardd'],
                             'UserName': 'mobile', 'KeepAlive': True, 'MachServices': {'kept': True},
                             'EnvironmentVariables': {'KEEP_EXISTING': 'yes'}},
                             '/other/job.plist': {'Label': 'other'}}}

    def test_only_exact_environment_key_changes_and_input_unchanged(self):
        baseline = copy.deepcopy(self.original)
        patched = embed.backboard_ignore_mach_send_errors(self.original)
        expected = copy.deepcopy(baseline)
        expected['LaunchDaemons'][embed.BACKBOARD_PLIST_DEST]['EnvironmentVariables']['CA_IGNORE_MACH_SEND_ERRORS'] = '1'
        self.assertEqual(self.original, baseline)
        self.assertEqual(patched, expected)
        self.assertEqual(plistlib.loads(plistlib.dumps(patched, fmt=plistlib.FMT_BINARY)), expected)
        self.assertEqual(embed.backboard_ignore_mach_send_errors(patched), expected)

    def test_absent_environment(self):
        job = self.original['LaunchDaemons'][embed.BACKBOARD_PLIST_DEST]
        del job['EnvironmentVariables']
        patched = embed.backboard_ignore_mach_send_errors(self.original)
        self.assertEqual(patched['LaunchDaemons'][embed.BACKBOARD_PLIST_DEST]['EnvironmentVariables'],
                         {'CA_IGNORE_MACH_SEND_ERRORS': '1'})

    def test_wrong_job_or_environment_rejected(self):
        for field, value in [('Label', 'other'), ('ProgramArguments', ['/other/backboardd']),
                             ('EnvironmentVariables', ['bad']), ('EnvironmentVariables', {'KEY': 1})]:
            with self.subTest(field=field, value=value):
                candidate = copy.deepcopy(self.original)
                candidate['LaunchDaemons'][embed.BACKBOARD_PLIST_DEST][field] = value
                with self.assertRaises(ValueError):
                    embed.backboard_ignore_mach_send_errors(candidate)
        for cache in ({}, {'LaunchDaemons': {}}, {'LaunchDaemons': []}):
            with self.assertRaises(ValueError):
                embed.backboard_ignore_mach_send_errors(cache)


if __name__ == '__main__':
    unittest.main()
