#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Independent double-precision sampling checks for the integer GPU oracle."""
import math
import unittest
from build_runtime_linear_blur_fixture import bilinear16, expected_pixels


def source_pattern():
    source = bytearray(16384)
    for y in range(64):
        for x in range(64):
            b, g = (x//7)&1, (y//7)&1
            source[(y*64+x)*4:(y*64+x)*4+4] = bytes((b*255, g*255, (b^g)*255, 255))
    return source


def float_oracle(source):
    def sample(u, v, channel):
        x, y = math.floor(u-.5), math.floor(v-.5)
        fx, fy = u-.5-x, v-.5-y
        result = 0
        for dy in (0, 1):
            for dx in (0, 1):
                at = (min(63, max(0, y+dy))*64+min(63, max(0, x+dx)))*4+channel
                result += source[at]/255 * (fx if dx else 1-fx) * (fy if dy else 1-fy)
        return result
    result = bytearray()
    for y in range(32):
        for x in range(32):
            for c in range(3):
                total = sum(sample(-1.75+2*(x+.5)+dx, .25+2*(y+.5)+dy, c)
                            for dy in (-1.5, -.5, .5, 1.5) for dx in (-1.5, -.5, .5, 1.5))
                result.append(round(total/16*.5*255))
            result.append(255)
    return bytes(result)


class LinearOracle(unittest.TestCase):
    def test_exact_quarter_weights_and_edge_clamp(self):
        source = bytearray(16384)
        source[0] = 255
        self.assertEqual(bilinear16(source, 1, 1, 0), 9)
        self.assertEqual(bilinear16(source, 3, 3, 0), 1)
        self.assertEqual(bilinear16(source, -3, -3, 0), 16)
        source[-4] = 255
        self.assertEqual(bilinear16(source, 255, 255, 0), 16)

    def test_all_4096_bytes_against_independent_float_model(self):
        source = source_pattern()
        actual = expected_pixels(source)
        self.assertEqual(actual, float_oracle(source))
        self.assertEqual(actual[3::4], bytes([255])*1024)
        self.assertGreater(len(set(actual[0::4])), 5)
        self.assertGreater(sum(abs(a-b)>1 for a, b in zip(actual, expected_pixels(source, False))), 128)

    def test_reject_nonbinary_source(self):
        source = source_pattern()
        source[0] = 127
        with self.assertRaises(ValueError):
            bilinear16(source, 0, 0, 0)


if __name__ == '__main__':
    unittest.main()
