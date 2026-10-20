#!/usr/bin/env python3
"""Write an Android boot image, header v3 (bramble), without AOSP mkbootimg.

v3 has no dtb, base or offsets: ABL takes the DTB from vendor_boot and puts
vendor_boot's ramdisk in front of ours. Page size is fixed at 4096.

  mkbootv3.py --kernel Image [--ramdisk rd.bin] -o boot.img
"""
import argparse
import gzip
import struct

PAGE = 4096
HEADER_SIZE = 1580  # boot_img_hdr_v3


def empty_cpio():
    """gzip'd newc cpio holding only the trailer (ABL dislikes size 0)."""
    name = b'TRAILER!!!\0'
    hdr = b'070701' + b''.join(b'%08X' % v for v in
                               (0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, len(name), 0))
    body = hdr + name
    body += b'\0' * (-len(body) % 4)
    body += b'\0' * (-len(body) % 512)
    return gzip.compress(body, 9, mtime=0)


def os_version(ver, patch):
    a, b, c = (int(x) for x in ver.split('.'))
    y, m = (int(x) for x in patch.split('-'))
    return ((a << 14 | b << 7 | c) << 11) | ((y - 2000) << 4 | m)


def pad(b):
    return b + b'\0' * (-len(b) % PAGE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kernel', required=True)
    ap.add_argument('--ramdisk')
    ap.add_argument('--cmdline', default='console=null')
    # Stock bramble boot_a (UP1A.231105.001.B2) carries 16.0.0 / 2026-08.
    ap.add_argument('--os_version', default='16.0.0')
    ap.add_argument('--os_patch_level', default='2026-08')
    ap.add_argument('-o', '--out', required=True)
    a = ap.parse_args()

    kernel = open(a.kernel, 'rb').read()
    ramdisk = open(a.ramdisk, 'rb').read() if a.ramdisk else empty_cpio()
    cmdline = a.cmdline.encode()
    assert len(cmdline) < 1536, 'cmdline too long'

    hdr = struct.pack('<8sIIII4II1536s', b'ANDROID!', len(kernel), len(ramdisk),
                      os_version(a.os_version, a.os_patch_level), HEADER_SIZE,
                      0, 0, 0, 0, 3, cmdline)
    assert len(hdr) == HEADER_SIZE
    with open(a.out, 'wb') as f:
        f.write(pad(hdr) + pad(kernel) + pad(ramdisk))


if __name__ == '__main__':
    main()
