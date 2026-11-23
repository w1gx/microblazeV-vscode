# Author: w1gx
# Date:   2026-11-22
#
# MicroBlaze V on Arty A7-100, built without Vitis.
#
#   make hw        rebuild the hardware (~15 min; never started implicitly)
#                  and generate the BSP (drivers for every IP, libraries) for it
#   make bsp       regenerate only the BSP, e.g. after editing sw/bsp.conf
#   make gui       open the block design in Vivado (toolbar: MBV: Export BD,
#                  MBV: Build HW + BSP); FRESH=1 recreates it from hw/system_bd.tcl
#   make           build the software and merge it into the bitstream (seconds)
#   APP=<name>     which program in sw/apps/ (default demo), e.g. make run APP=echo
#   make program   load build/sw/download.bit over JTAG
#   make flash     write it to the SPI flash (boots at power-up)
#   make run       configure the FPGA with the plain hardware and load app.elf through the
#                  debugger (for programs that run from DDR, e.g. APP=echo)
#   make debug-load  load APP halted at its entry point for the debugger (GDB, port 3004);
#                  FILE=sw/apps/<name>/... instead of APP picks the program a source file belongs to
#   make console   serial terminal on the Arty USB-UART (Ctrl-] quits)
#   make clean     remove build/sw     make distclean   remove all of build/

HW_OUT := build/hw/out
HW_SRC := hw/system_bd.tcl hw/build_hw.tcl hw/project.tcl hw/gen_memmap.tcl hw/arty_a7_100.xdc
BSP_LIB := build/bsp/domain/lib/libxil.a

.PHONY: all hw hw-check gui bsp sw debug-load program flash run console clean distclean
all: sw

# The hardware build takes ~15 min, so it never starts implicitly: `make hw`
# runs it, `make` only warns when hw/ is newer than the bitstream.
hw:
	./hw/build_hw.sh

$(HW_OUT)/system.bit:
	@echo "No hardware build yet - run 'make hw' first (~15 min)."; exit 1

# Compares against source.fingerprint (written by a build, touched when `make hw` finds
# the outputs up to date), so a file git rewrote with the same content stops warning
# after one `make hw`. Older builds without the file fall back to system.bit.
HW_STAMP = $(firstword $(wildcard $(HW_OUT)/source.fingerprint) $(HW_OUT)/system.bit)
hw-check: $(HW_OUT)/system.bit
	@for f in $(HW_SRC); do [ $$f -nt $(HW_STAMP) ] && \
	    echo "WARNING: $$f is newer than the bitstream - run 'make hw' (or MBV: Build HW + BSP)"; done; true

gui:
	./scripts/gui.sh

bsp: $(BSP_LIB)
$(BSP_LIB): $(HW_OUT)/system.xsa sw/bsp.conf scripts/build_bsp.sh
	./scripts/build_bsp.sh

APP ?= demo
# FILE=sw/apps/<name>/... (any depth, e.g. a file in modules/) picks the program it belongs to
ifneq ($(FILE),)
APP := $(word 3,$(subst /, ,$(FILE)))
endif
export APP

sw: hw-check $(BSP_LIB)
	$(MAKE) -C sw

program: sw
	./scripts/program.sh

# DDR programs are flashed together with the bootloader (sw/apps/boot).
flash: sw
	@if [ "$$($(MAKE) -s --no-print-directory -C sw APP=$(APP) print-run-from)" = DDR ]; then \
	    $(MAKE) -C sw APP=boot; fi
	./scripts/flash.sh

run: hw-check $(BSP_LIB)
	$(MAKE) -C sw elf
	./scripts/run.sh -p

# For the debugger (VS Code "Debug <app>"): configure the FPGA, load the program
# and leave the CPU halted at its entry point; GDB then attaches on port 3004.
# build/sw/debug-app links to the loaded program's directory ("Debug program of open file").
debug-load: hw-check $(BSP_LIB)
	$(MAKE) -C sw elf
	ln -sfn $(APP) build/sw/debug-app
	./scripts/run.sh -p -s

console:
	./scripts/console.py

clean:
	rm -rf build/sw

distclean:
	rm -rf build
