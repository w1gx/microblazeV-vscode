# Author: w1gx
# Date:   2026-11-22
#
# lwIP needs several MB of buffers (2048 pbufs, see sw/bsp.conf): run from DDR.
# Load with `make run APP=echo` (xsdb); updatemem can only fill the local memory.
RUN_FROM := DDR

# The template calls xil_printf/print without including the header (Vitis tolerates it).
APP_CFLAGS := -include xil_printf.h
