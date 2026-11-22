/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Bootloader for programs that run from DDR.
 *
 * Runs from the local memory (it is part of the bitstream), so it starts at
 * power-up, after PROG and after RESET. It reads the image that
 * `make flash APP=<name>` stored at MBV_IMAGE_FLASH_OFFSET in the QSPI flash
 * (format: sw/common/mbv_image.h), checks it, copies it to DDR and jumps to
 * its entry point. The program's own startup code then sets up everything
 * else (stack, .bss, trap vector).
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "xparameters.h"
#include "xspi.h"
#include "xstatus.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "mbv_image.h"

#define CHUNK   256u                    /* bytes per SPI read command */
#define DDR_LO  XPAR_MIG_0_BASEADDRESS
#define DDR_HI  XPAR_MIG_0_HIGHADDRESS

static XSpi spi;
static u8 tx[4 + CHUNK], rx[4 + CHUNK];

/* Read from the flash with the plain READ command (0x03, 3-byte address). */
static int flash_read(u32 addr, u8 *dst, u32 len)
{
    while (len) {
        u32 n = len < CHUNK ? len : CHUNK;
        tx[0] = 0x03;
        tx[1] = (u8)(addr >> 16);
        tx[2] = (u8)(addr >> 8);
        tx[3] = (u8)addr;
        if (XSpi_Transfer(&spi, tx, rx, 4 + n) != XST_SUCCESS)
            return -1;
        memcpy(dst, rx + 4, n);
        addr += n;
        dst += n;
        len -= n;
    }
    return 0;
}

/* CRC-32 as in zlib (reflected, polynomial 0xEDB88320), continued from crc. */
static u32 crc32(u32 crc, const u8 *p, u32 n)
{
    crc = ~crc;
    while (n--) {
        crc ^= *p++;
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1));
    }
    return ~crc;
}

static void fail(const char *why)
{
    xil_printf("boot: %s\r\n", why);
    xil_printf("boot: no program started. Store one with: make flash APP=<name>\r\n");
    for (;;)
        ;
}

int main(void)
{
    static struct mbv_image_header h;

    xil_printf("\r\n\r\nMicroBlaze V bootloader: image at flash 0x%08x\r\n", MBV_IMAGE_FLASH_OFFSET);

    if (XSpi_Initialize(&spi, XPAR_XSPI_0_BASEADDR) != XST_SUCCESS ||
        XSpi_SetOptions(&spi, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION) != XST_SUCCESS ||
        XSpi_Start(&spi) != XST_SUCCESS)
        fail("SPI init failed");
    XSpi_IntrGlobalDisable(&spi);                   /* polled mode */
    XSpi_SetSlaveSelect(&spi, 0x01);

    if (flash_read(MBV_IMAGE_FLASH_OFFSET, (u8 *)&h, sizeof h) != 0)
        fail("flash read failed");
    if (h.magic != MBV_IMAGE_MAGIC)
        fail("no image in flash (wrong magic)");
    if (h.version != MBV_IMAGE_VERSION || h.nseg == 0 || h.nseg > MBV_IMAGE_MAX_SEGMENTS)
        fail("unsupported image");
    if (crc32(0, (const u8 *)&h, offsetof(struct mbv_image_header, header_crc)) != h.header_crc)
        fail("image header CRC mismatch");

    char name[sizeof h.name + 1];
    memcpy(name, h.name, sizeof h.name);
    name[sizeof h.name] = 0;
    xil_printf("boot: loading '%s', %d bytes in %d segment(s) ...\r\n", name, (int)h.payload_size, (int)h.nseg);

    u32 crc = 0;
    for (u32 i = 0; i < h.nseg; i++) {
        const struct mbv_image_segment *s = &h.seg[i];
        if (s->addr < DDR_LO || s->addr + s->size - 1 > DDR_HI || s->addr + s->size < s->addr)
            fail("segment outside DDR");
        if (flash_read(MBV_IMAGE_FLASH_OFFSET + s->offset, (u8 *)(UINTPTR)s->addr, s->size) != 0)
            fail("flash read failed");
        xil_printf("boot:   0x%08x  %d bytes\r\n", s->addr, (int)s->size);
        crc = crc32(crc, (const u8 *)(UINTPTR)s->addr, s->size);   /* check what is in DDR */
    }
    if (crc != h.payload_crc)
        fail("CRC mismatch after loading (flash or DDR problem)");

    Xil_DCacheFlush();                              /* data written through the D-cache ... */
    Xil_ICacheInvalidate();                         /* ... must not meet stale I-cache lines */

    xil_printf("boot: CRC ok, starting '%s' at 0x%08x\r\n\r\n", name, h.entry);
    ((void (*)(void))(UINTPTR)h.entry)();
    fail("program returned");
    return 0;
}
