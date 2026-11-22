/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Linker script for the MicroBlaze V with AMD's standalone runtime (BSP).
 * Based on the lscript.ld Vitis generates, with all sections in one region:
 *
 *   CODE = LMB (default): the program is baked into the bitstream with
 *          updatemem and starts at power-up from the reset vector 0x0.
 *   CODE = DDR (make RUN_FROM=DDR): for big programs, e.g. with lwIP; load
 *          them with scripts/run.sh.
 *
 * memory.ld (generated from the block design) defines LMB and DDR; the
 * Makefile adds REGION_ALIAS("CODE", ...).
 *
 *   [_boot][.text][.rodata][.data][.sdata][.sbss/.bss][heap ->      <- stack]
 *
 * With CODE = LMB, put big buffers in DDR with
 *   static uint8_t buf[N] __attribute__((section(".ddr")));
 * (not zeroed, not loaded by updatemem).
 */
INCLUDE memory.ld
INCLUDE region.ld

ENTRY(_boot)

_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x2000;  /* 8 KB */
_MIN_HEAP   = DEFINED(_MIN_HEAP)   ? _MIN_HEAP   : 0x1000;  /* link fails if less is left */

SECTIONS
{
    .text.init : {
        __text.init_start = .;
        KEEP(*(.text.init))              /* _boot (standalone boot.S): reset vector */
        __text.init_end = .;
    } > CODE

    .text : {
        *(.text .text.* .gnu.linkonce.t.*)
    } > CODE

    .init : { KEEP(*(.init)) } > CODE
    .fini : { KEEP(*(.fini)) } > CODE

    .ctors : {
        __CTOR_LIST__ = .;
        ___CTORS_LIST___ = .;
        KEEP(*crtbegin.o(.ctors))
        KEEP(*(EXCLUDE_FILE(*crtend.o) .ctors))
        KEEP(*(SORT(.ctors.*)))
        KEEP(*(.ctors))
        __CTOR_END__ = .;
        ___CTORS_END___ = .;
    } > CODE
    .dtors : {
        __DTOR_LIST__ = .;
        ___DTORS_LIST___ = .;
        KEEP(*crtbegin.o(.dtors))
        KEEP(*(EXCLUDE_FILE(*crtend.o) .dtors))
        KEEP(*(SORT(.dtors.*)))
        KEEP(*(.dtors))
        __DTOR_END__ = .;
        ___DTORS_END___ = .;
    } > CODE

    .rodata : {
        __rodata_start = .;
        *(.rodata .rodata.* .gnu.linkonce.r.*)
        __rodata_end = .;
    } > CODE
    .srodata : {
        __srodata_start = .;
        *(.srodata .srodata.*)
        __srodata_end = .;
    } > CODE
    .sdata2 : {
        __sdata2_start = .;
        *(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
        __sdata2_end = .;
    } > CODE

    .drvcfg_sec : {                      /* driver config tables (*_g.c) */
        . = ALIGN(8);
        __drvcfgsecdata_start = .;
        KEEP(*(.drvcfg_sec))
        __drvcfgsecdata_end = .;
        __drvcfgsecdata_size = __drvcfgsecdata_end - __drvcfgsecdata_start;
    } > CODE

    .data : {
        __data_start = .;
        *(.data .data.* .gnu.linkonce.d.*)
        _edata = .;
    } > CODE

    .got  : { *(.got) }  > CODE
    .got1 : { *(.got1) } > CODE
    .got2 : { *(.got2) } > CODE
    .eh_frame : { KEEP(*(.eh_frame)) } > CODE
    .jcr : { *(.jcr) } > CODE
    .gcc_except_table : { *(.gcc_except_table) } > CODE

    .init_array : {
        __init_array_start = .;
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        __init_array_end = .;
    } > CODE
    .fini_array : {
        __fini_array_start = .;
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array))
        __fini_array_end = .;
    } > CODE

    .sdata : {
        __sdata_start = .;
        *(.sdata .sdata.* .gnu.linkonce.s.*)
        __sdata_end = .;
    } > CODE
    .tdata : {
        __tdata_start = .;
        *(.tdata .tdata.* .gnu.linkonce.td.*)
        __tdata_end = .;
    } > CODE
    .tbss : {
        __tbss_start = .;
        *(.tbss .tbss.* .gnu.linkonce.tb.*)
        __tbss_end = .;
    } > CODE

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.* .gnu.linkonce.b.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > CODE
    .sbss (NOLOAD) : {
        __sbss_start = .;
        *(.sbss .sbss.* .gnu.linkonce.sb.*)
        . = ALIGN(4);
        __sbss_end = .;
    } > CODE
    .sbss2 : {
        __sbss2_start = .;
        *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*)
        __sbss2_end = .;
    } > CODE

    _SDA_BASE_  = __sdata_start + ((__sbss_end - __sdata_start) / 2);
    _SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2);
    __global_pointer$ = MIN(__sdata_start + 0x800, MAX(__data_start + 0x800, __bss_end - 0x800));

    /* crt0 clears __bss_start.._end on every start. */
    _end = ALIGN(__sbss2_end, 8);
    end  = _end;

    /* Survives a CPU reset (RESET button): not cleared by crt0, not loaded by
       updatemem. Holds the pristine copy of the initialised data that
       sw/common/data_restore.c restores after a reset (the bitstream loads
       .data only once, at configuration). */
    .noinit (NOLOAD) : ALIGN(8) {
        __data_backup = .;
        . += __tdata_end - __drvcfgsecdata_start;
        . = ALIGN(4);
        __data_backup_tag = .;
        . += 8;
        *(.noinit .noinit.*)
    } > CODE

    .ddr (NOLOAD) : ALIGN(64) {
        *(.ddr .ddr.*)
    } > DDR

    /* Stack at the top of the region, heap gets everything in between
       (after .ddr when the program itself runs from DDR). */
    /* Not the very end of the region: boot.S does `sw zero,0(sp)` (argc) right after
       setting sp = __stack, so __stack must itself be writable memory. At the region
       end that store goes past the LMB/DDR and the CPU hangs before main(). 16 bytes
       keep the RISC-V stack alignment. */
    _stack       = ORIGIN(CODE) + LENGTH(CODE) - 16;
    __stack      = _stack;
    _stack_end   = _stack - _STACK_SIZE;
    _heap        = ALIGN(ADDR(.ddr) >= ORIGIN(CODE) && ADDR(.ddr) < ORIGIN(CODE) + LENGTH(CODE)
                         ? ADDR(.ddr) + SIZEOF(.ddr) : ADDR(.noinit) + SIZEOF(.noinit), 8);
    _heap_start  = _heap;
    _heap_end    = _stack_end;
    ASSERT(_heap_end >= _heap_start + _MIN_HEAP, "program does not fit in the CODE region")

    /DISCARD/ : { *(.note.GNU-stack) *(.note.gnu.build-id) *(.comment) }
}
