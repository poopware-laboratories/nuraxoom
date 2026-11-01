#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Minimal Android boot image (header v0) writer, as used by the Xoom bootloader."""
import argparse
import hashlib
import struct


def pad(data, page):
    return data + b'\0' * (-len(data) % page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kernel', required=True)
    ap.add_argument('--ramdisk', required=True)
    ap.add_argument('--cmdline', default='')
    ap.add_argument('--board', default='')
    ap.add_argument('--base', type=lambda x: int(x, 0), default=0x10000000)
    ap.add_argument('--kernel-offset', type=lambda x: int(x, 0), default=0x00008000)
    ap.add_argument('--ramdisk-offset', type=lambda x: int(x, 0), default=0x01000000)
    ap.add_argument('--second-offset', type=lambda x: int(x, 0), default=0x00f00000)
    ap.add_argument('--tags-offset', type=lambda x: int(x, 0), default=0x00000100)
    ap.add_argument('--pagesize', type=int, default=2048)
    ap.add_argument('-o', '--output', required=True)
    a = ap.parse_args()

    kernel = open(a.kernel, 'rb').read()
    ramdisk = open(a.ramdisk, 'rb').read()
    cmdline = a.cmdline.encode()
    if len(cmdline) > 511:
        raise SystemExit('cmdline longer than 511 bytes')
    if len(a.board) > 15:
        raise SystemExit('board name longer than 15 bytes')

    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, b''):
        sha.update(blob)
        sha.update(struct.pack('<I', len(blob)))
    ident = sha.digest() + b'\0' * 12

    hdr = struct.pack('<8s10I16s512s32s',
                      b'ANDROID!',
                      len(kernel), a.base + a.kernel_offset,
                      len(ramdisk), a.base + a.ramdisk_offset,
                      0, a.base + a.second_offset,
                      a.base + a.tags_offset, a.pagesize, 0, 0,
                      a.board.encode().ljust(16, b'\0'),
                      cmdline.ljust(512, b'\0'),
                      ident)
    with open(a.output, 'wb') as f:
        f.write(pad(hdr, a.pagesize))
        f.write(pad(kernel, a.pagesize))
        f.write(pad(ramdisk, a.pagesize))


if __name__ == '__main__':
    main()
