/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Flash image format for programs that run from DDR (e.g. sw/apps/echo).
 *
 * scripts/mkimage.py writes it from app.elf, `make flash APP=<name>` stores it
 * in the QSPI flash at MBV_IMAGE_FLASH_OFFSET, and the bootloader
 * (sw/apps/boot) copies it to DDR at every start. scripts/flash.sh and
 * scripts/mkimage.py read the values below from this file.
 *
 *   flash 0x000000  bitstream with the bootloader in the local memory (~2.2 MB)
 *   flash 0x400000  struct mbv_image_header (256 bytes), then the segments
 */
#ifndef MBV_IMAGE_H
#define MBV_IMAGE_H

#include <stdint.h>

#define MBV_IMAGE_FLASH_OFFSET  0x00400000u     /* 4 MB: above the largest bitstream */
#define MBV_IMAGE_MAGIC         0x4956424Du     /* "MBVI" little-endian */
#define MBV_IMAGE_VERSION       1u
#define MBV_IMAGE_HEADER_SIZE   256u            /* segment data starts here */
#define MBV_IMAGE_MAX_SEGMENTS  8u

struct mbv_image_segment {
    uint32_t addr;          /* load address (DDR) */
    uint32_t size;          /* bytes */
    uint32_t offset;        /* from the start of the image */
};

struct mbv_image_header {
    uint32_t magic;
    uint32_t version;
    uint32_t entry;         /* jump address, e.g. 0x80000000 */
    uint32_t nseg;
    uint32_t payload_size;  /* sum of segment sizes */
    uint32_t payload_crc;   /* CRC-32 (zlib) over all segments, in order */
    char     name[16];      /* program name, NUL padded */
    struct mbv_image_segment seg[MBV_IMAGE_MAX_SEGMENTS];
    uint32_t header_crc;    /* CRC-32 over all bytes above */
};

#endif
