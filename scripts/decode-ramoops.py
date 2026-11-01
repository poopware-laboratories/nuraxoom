#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Decode a raw ramoops dump saved by NuraXoom-save-crashlog.zip.
#   scripts/decode-ramoops.py ramoops-XXXX.bin
# Layout must match the wingray DTS: 1 MiB, record 128K, console 256K, pmsg 128K.
import struct
import sys
import zlib

SIG = 0x43474244  # "DBGC", persistent_ram_buffer signature
SIZE, RECORD, CONSOLE, PMSG = 0x100000, 0x20000, 0x40000, 0x20000


def zone(buf, off, size):
    sig, start, used = struct.unpack_from("<III", buf, off)
    if sig != SIG:
        return None
    data = buf[off + 12:off + size]
    used, start = min(used, len(data)), min(start, len(data))
    # Ring buffer: once full, the oldest byte is at "start".
    return data[start:used] + data[:start] if used == len(data) else data[:used]


def text(b):
    # Dump records: "====<time>-<C|D>\n" header, then the (maybe deflate
    # compressed, CONFIG_PSTORE_COMPRESS) log.
    hdr = ""
    if b.startswith(b"===="):
        hdr, _, b = b.partition(b"\n")
        hdr = hdr.decode(errors="replace") + "\n"
    for wbits in (15, -15):
        try:
            return hdr + zlib.decompress(b, wbits).decode(errors="replace")
        except zlib.error:
            pass
    return hdr + b.decode(errors="replace")


buf = open(sys.argv[1], "rb").read()
dump_sz = SIZE - CONSOLE - PMSG
zones = [("dmesg-%d" % i, i * RECORD, RECORD) for i in range(dump_sz // RECORD)]
zones += [("console", dump_sz, CONSOLE), ("pmsg", dump_sz + CONSOLE, PMSG)]
for name, off, size in zones:
    z = zone(buf, off, size)
    if z is None:
        print("== %s: no ramoops signature" % name)
    elif not z:
        print("== %s: empty" % name)
    else:
        print("== %s (%d bytes)" % (name, len(z)))
        print(text(z).rstrip("\0"))
