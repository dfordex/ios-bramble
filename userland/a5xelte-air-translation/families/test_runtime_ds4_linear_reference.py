#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Separate normalized-coordinate floating point check of DS4 integer oracle."""
import math
import unittest
from build_runtime_ds4_linear_fixture import expected_pixels


def source_pattern():
    data = bytearray()
    for y in range(64):
        for x in range(64):
            b, g = (x//7)&1, (y//7)&1
            data.extend((255*b, 255*g, 255*(b^g), 255))
    return data


def float_reference(source):
    def sample(u, v, channel):
        # Compute from normalized texture coordinates and clamp each neighbor.
        sx, sy = u*64-.5, v*64-.5
        x, y = math.floor(sx), math.floor(sy)
        fx, fy = sx-x, sy-y
        return sum(source[(min(63,max(0,y+dy))*64+min(63,max(0,x+dx)))*4+channel]/255
                   * (fx if dx else 1-fx) * (fy if dy else 1-fy)
                   for dy in (0,1) for dx in (0,1))
    out = bytearray()
    taps = ((-.5,-.5,.125),(.5,-.5,.125),(-.5,.5,.25),(.5,.5,.5))
    for y in range(32):
        for x in range(32):
            for channel in range(3):
                uv = ((-1.75+2*(x+.5))/64, (.25+2*(y+.5))/64)
                total = sum(w*sample(uv[0]+dx/64, uv[1]+dy/64, channel)
                            for dx,dy,w in taps)
                out.append(round(total*.5*255))
            out.append(255)
    return bytes(out)


class DS4LinearReference(unittest.TestCase):
    def test_full_frame_against_normalized_float_sampling(self):
        source = source_pattern()
        pixels = expected_pixels(source)
        self.assertEqual(pixels, float_reference(source))
        self.assertEqual(pixels[3::4], bytes([255])*1024)
        self.assertEqual((min(pixels[0::4]), max(pixels[0::4])), (0,128))
        self.assertGreater(sum(abs(a-b)>1 for a,b in zip(pixels,expected_pixels(source,False))), 128)

    def test_constant_and_clamped_source(self):
        self.assertEqual(expected_pixels(bytes([255])*16384), bytes([128,128,128,255])*1024)
        self.assertEqual(expected_pixels(bytes([0,0,0,255])*4096), bytes([0,0,0,255])*1024)


if __name__ == '__main__':
    unittest.main()
