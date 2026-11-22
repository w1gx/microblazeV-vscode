#!/usr/bin/env python3
# Author: w1gx
# Date:   2026-11-22

"""Turn a DDR program's app.elf into a flash image for the bootloader.

    scripts/mkimage.py <app.elf> <app.img> [--name NAME]

Stores the ELF's PT_LOAD segments (file contents only; .bss and other
zero-initialised parts are cleared by the program's own startup code) behind a
256-byte header. The format and constants are in sw/common/mbv_image.h.
"""
import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

HDR = Path(__file__).resolve().parent.parent / "sw" / "common" / "mbv_image.h"


def constants():
    text = HDR.read_text()
    vals = {}
    for name in ("MBV_IMAGE_MAGIC", "MBV_IMAGE_VERSION", "MBV_IMAGE_HEADER_SIZE",
                 "MBV_IMAGE_MAX_SEGMENTS", "MBV_IMAGE_FLASH_OFFSET"):
        m = re.search(rf"#define\s+{name}\s+(0x[0-9A-Fa-f]+|\d+)u?", text)
        if not m:
            sys.exit(f"mkimage: {name} not found in {HDR}")
        vals[name] = int(m.group(1), 0)
    return vals


def load_segments(elf):
    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        sys.exit("mkimage: not a 32-bit little-endian ELF")
    entry, phoff = struct.unpack_from("<II", elf, 24)
    phentsize, phnum = struct.unpack_from("<HH", elf, 42)
    segs = []
    for i in range(phnum):
        p_type, p_offset, p_vaddr, p_paddr, p_filesz = struct.unpack_from("<IIIII", elf, phoff + i * phentsize)
        if p_type == 1 and p_filesz > 0:                 # PT_LOAD with file contents
            segs.append((p_paddr, elf[p_offset:p_offset + p_filesz]))
    return entry, segs


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("elf")
    ap.add_argument("img")
    ap.add_argument("--name", default="")
    ap.add_argument("--ddr", default="0x80000000:0x10000000",
                    help="allowed load range base:size (default: the Arty's DDR3)")
    a = ap.parse_args()
    c = constants()

    entry, segs = load_segments(Path(a.elf).read_bytes())
    if not segs:
        sys.exit("mkimage: no loadable segments")
    if len(segs) > c["MBV_IMAGE_MAX_SEGMENTS"]:
        sys.exit(f"mkimage: {len(segs)} segments, the bootloader handles {c['MBV_IMAGE_MAX_SEGMENTS']}")
    base, size = (int(x, 0) for x in a.ddr.split(":"))
    for addr, data in segs:
        if not (base <= addr and addr + len(data) <= base + size):
            sys.exit(f"mkimage: segment 0x{addr:08x}+{len(data)} is outside DDR - "
                     "only programs linked with RUN_FROM=DDR can be booted from flash")

    table, payload, off = [], b"", c["MBV_IMAGE_HEADER_SIZE"]
    for addr, data in segs:
        pad = (-len(data)) % 4
        table.append((addr, len(data), off))
        payload += data + b"\0" * pad
        off += len(data) + pad
    seg_crc_data = b"".join(data for _, data in segs)

    hdr = struct.pack("<6I16s", c["MBV_IMAGE_MAGIC"], c["MBV_IMAGE_VERSION"], entry, len(segs),
                      len(seg_crc_data), zlib.crc32(seg_crc_data), a.name.encode()[:15])
    for i in range(c["MBV_IMAGE_MAX_SEGMENTS"]):
        hdr += struct.pack("<3I", *(table[i] if i < len(table) else (0, 0, 0)))
    hdr += struct.pack("<I", zlib.crc32(hdr))
    hdr += b"\xff" * (c["MBV_IMAGE_HEADER_SIZE"] - len(hdr))

    Path(a.img).write_bytes(hdr + payload)
    print(f"mkimage: {a.img}: '{a.name}', entry 0x{entry:08x}, {len(segs)} segment(s), "
          f"{len(seg_crc_data)} bytes -> flash 0x{c['MBV_IMAGE_FLASH_OFFSET']:08x}")


if __name__ == "__main__":
    main()
