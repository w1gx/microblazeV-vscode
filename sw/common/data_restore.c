/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Make programs restartable with the board's RESET button.
 *
 * A program in the local memory gets its initialised data (.data, .sdata,
 * driver config tables, ...) from the bitstream, i.e. only once, when the FPGA
 * is configured. RESET restarts the CPU without reloading the memory: crt0
 * clears .bss again, but .data keeps the values of the previous run. newlib's
 * stdio state lives there, so after a reset printf() silently printed nothing.
 *
 * On the first start after configuration this saves the initialised data to
 * .noinit (see sw/link.ld); on every later start it restores it. The copy is
 * tagged with __mbv_link_id, a value that changes with every link, so a copy
 * left by another build (e.g. in DDR) is never restored.
 *
 * Runs as the first constructor, before main() and before newlib uses stdio.
 * Linked into every program in sw/apps/ (sw/Makefile, sw/common/).
 */
#include <stdint.h>
#include <string.h>

#define TAG_MAGIC 0x4D425644u   /* "MBVD" */

extern char __drvcfgsecdata_start[], __tdata_end[];   /* initialised data, see link.ld */
extern char __data_backup[];
extern uint32_t __data_backup_tag[2];                 /* magic, link id */
extern char __mbv_link_id[];                          /* --defsym, address = id */

__attribute__((constructor(101), used))
static void mbv_data_restore(void)
{
    const uint32_t id = (uint32_t)(uintptr_t)__mbv_link_id;
    const size_t n = (size_t)(__tdata_end - __drvcfgsecdata_start);

    if (__data_backup_tag[0] == TAG_MAGIC && __data_backup_tag[1] == id) {
        memcpy(__drvcfgsecdata_start, __data_backup, n);    /* restart: restore */
    } else {
        memcpy(__data_backup, __drvcfgsecdata_start, n);    /* first start: save */
        __data_backup_tag[1] = id;
        __data_backup_tag[0] = TAG_MAGIC;
    }
}
