#!/usr/bin/env python3
"""Write an Android boot image, header v3 (bramble), without AOSP mkbootimg.

v3 has no dtb, base or offsets: ABL takes the DTB from vendor_boot and puts
vendor_boot's ramdisk in front of ours. Page size is fixed at 4096.

  mkbootv3.py --kernel Image [--ramdisk rd.bin] -o boot.img
"""
import argparse
import gzip
import hashlib
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


def pad8(b):
    return b + b'\0' * (-len(b) % 8)


def avb_prop(key, value):
    k, v = key.encode(), value.encode()
    body = struct.pack('>QQ', len(k), len(v)) + k + b'\0' + v + b'\0'
    return pad8(struct.pack('>QQ', 0, len(pad8(body))) + body)


def avb_hash(image, partition):
    digest = hashlib.sha256(image).digest()
    body = (struct.pack('>Q32sIIII60x', len(image), b'sha256', len(partition), 0,
                        len(digest), 0) + partition + digest)
    return struct.pack('>QQ', 2, len(pad8(body))) + pad8(body)


def avb_footer(image, partition_size, props):
    """Append an unsigned (algorithm NONE) vbmeta + AVBf footer like avbtool
    add_hash_footer. bramble's ABL reads os_version from these properties and
    refuses a boot.img without them; unlocked, it accepts no signature."""
    desc = avb_hash(image, b'boot') + b''.join(avb_prop(k, v) for k, v in props)
    aux = desc + b'\0' * (-len(desc) % 64)
    hdr = struct.pack('>4sIIQQIQQQQQQQQQQQII48s80x', b'AVB0', 1, 0, 0, len(aux), 0,
                      0, 0, 0, 0, 0, 0, 0, 0, 0, len(desc), 0, 0, 0, b'mkbootv3')
    assert len(hdr) == 256
    vbmeta = hdr + aux
    footer = struct.pack('>4sIIQQQ28x', b'AVBf', 1, 0, len(image), len(image), len(vbmeta))
    out = image + vbmeta
    assert len(out) + len(footer) <= partition_size, 'image too large for partition'
    return out + b'\0' * (partition_size - len(out) - len(footer)) + footer


def avb_borrow(image, stock):
    """Reuse a stock boot image's signed vbmeta and footer, as Magisk does.
    bramble's ABL rejects unsigned vbmeta ("Unsupported") but, unlocked,
    accepts a signed one whose hash no longer matches."""
    footer = stock[-64:]
    assert footer[:4] == b'AVBf', 'stock image has no AVB footer'
    orig, vb_off, vb_size = struct.unpack('>QQQ', footer[12:36])
    assert len(image) <= vb_off, 'image larger than the stock one'
    out = image + b'\0' * (vb_off - len(image)) + stock[vb_off:vb_off + vb_size]
    return out + b'\0' * (len(stock) - len(out) - 64) + footer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kernel', required=True)
    ap.add_argument('--ramdisk')
    ap.add_argument('--cmdline', default='console=null')
    # Stock bramble boot_a (UP1A.231105.001.B2) carries 16.0.0 / 2026-08.
    ap.add_argument('--os_version', default='16.0.0')
    ap.add_argument('--os_patch_level', default='2026-08')
    # boot_a/boot_b are 96 MiB; the AVB footer sits in the last 64 bytes.
    ap.add_argument('--partition_size', type=lambda s: int(s, 0), default=0x6000000)
    # AVB properties of the installed boot_a (LineageOS, BP4A.251205.006).
    ap.add_argument('--avb_os_version', default='16')
    ap.add_argument('--avb_security_patch', default='2023-11-05')
    ap.add_argument('--avb_from', help='stock boot image whose signed vbmeta to reuse')
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
    image = pad(hdr) + pad(kernel) + pad(ramdisk)
    if a.avb_from:
        image = avb_borrow(image, open(a.avb_from, 'rb').read())
    else:
        image = avb_footer(image, a.partition_size, [
            ('com.android.build.boot.os_version', a.avb_os_version),
            ('com.android.build.boot.security_patch', a.avb_security_patch)])
    with open(a.out, 'wb') as f:
        f.write(image)


if __name__ == '__main__':
    main()
