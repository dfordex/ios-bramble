#!/usr/bin/env python3
"""Explicit optional-test overrides retain native/UI boot configuration."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("metal_boot_packer", HERE / "a5xelte-pack-metal-boot.py")
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


def overrides(*flags):
    args = packer.argument_parser().parse_args(['reference.img', 'kernel', 'candidate.img', *flags])
    return packer.selftest_boot_arguments(args)


class OptionalTestArguments(unittest.TestCase):
    def test_skip_replaces_every_inherited_enable(self):
        original = ['a5shadersuite=1', 'cpus=4', 'a5downsampletest=1',
                    'a5shadersuite=1', 'a5downsampletest=1']
        result = packer.rewrite_boot_arguments(original,
                    overrides('--skip-shader-suite', '--skip-downsample'))
        self.assertEqual(result, ['cpus=4', 'a5shadersuite=0', 'a5downsampletest=0'])
        self.assertEqual(original.count('a5shadersuite=1'), 2)

    def test_native_and_unrelated_arguments_retained(self):
        native = ['a5gpu=8', 'a5gpuclient=1', 'a5metal=1', 'a5native=1',
                  'a5fb_gpu=1', 'cpus=4', 'a5emmc_blocks=32', '-enable_kprintf_spam',
                  'sweetnull=backboardd,a5mali-metal-probe,a5shader-compile']
        result = packer.rewrite_boot_arguments(native + ['a5shadersuite=1', 'a5downsampletest=1'],
                    overrides('--native-rendering', '--install-bundle',
                              '--skip-shader-suite', '--skip-downsample'))
        self.assertEqual(result, native + ['a5shadersuite=0', 'a5downsampletest=0'])

    def test_omitted_choices_preserve_reference(self):
        original = ['a5shadersuite=1', 'a5downsampletest=1', 'a5native=1']
        self.assertEqual(overrides(), {})
        self.assertEqual(packer.rewrite_boot_arguments(original, overrides()), original)

    def test_explicit_tests_replace_inherited_skip(self):
        result = packer.rewrite_boot_arguments(['a5shadersuite=0', 'a5downsampletest=0'],
                    overrides('--test-shader-suite', '--test-downsample'))
        self.assertEqual(result, ['a5shadersuite=1', 'a5downsampletest=1'])

    def test_individual_skip_changes_only_its_test(self):
        result = packer.rewrite_boot_arguments(['a5shadersuite=1', 'a5downsampletest=1'],
                    overrides('--skip-shader-suite'))
        self.assertEqual(result, ['a5downsampletest=1', 'a5shadersuite=0'])

    def test_conflicts_reject_before_reading_inputs(self):
        for enable, skip in (('--test-shader-suite', '--skip-shader-suite'),
                             ('--test-downsample', '--skip-downsample'),
                             ('--present-damage', '--full-frame-present')):
            result = subprocess.run([sys.executable, str(HERE / 'a5xelte-pack-metal-boot.py'),
                    'nonexistent-reference.img', 'nonexistent-kernel', 'nonexistent-output.img',
                    enable, skip], capture_output=True, text=True)
            with self.subTest(enable=enable):
                self.assertEqual(result.returncode, 2)
                self.assertIn(f'argument {skip}: not allowed with argument {enable}', result.stderr)
                self.assertNotIn('FileNotFoundError', result.stderr)

    def test_presentation_override_removes_inherited_duplicates(self):
        native = ['a5fb_gpu=1', 'a5native=1', 'a5fb_hz=30', 'cpus=4']
        original = native + ['a5fb_damage=1', 'a5fb_damage=1']
        for flag, expected in (('--full-frame-present', '0'), ('--present-damage', '1')):
            args = packer.argument_parser().parse_args(['r', 'k', 'o', flag])
            actual = packer.rewrite_boot_arguments(original, packer.presentation_boot_arguments(args))
            self.assertEqual(actual, native + ['a5fb_damage=' + expected])
        args = packer.argument_parser().parse_args(['r', 'k', 'o'])
        self.assertEqual(packer.presentation_boot_arguments(args), {})


if __name__ == '__main__':
    unittest.main()
