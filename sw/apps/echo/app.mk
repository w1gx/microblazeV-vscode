# Author: w1gx
# Date:   2026-11-22
#
# lwIP needs several MB of buffers (2048 pbufs, see sw/bsp.conf): run from DDR.
# Load with `make run APP=echo` (xsdb); updatemem can only fill the local memory.
RUN_FROM := DDR

# The template calls xil_printf/print without including the header (Vitis tolerates it).
APP_CFLAGS := -include xil_printf.h

# AMD's template files stay as copied: relax the warnings the Makefile adds beyond
# -Wall -Wextra for them only (K&R-style "()" prototypes, missing prototypes, a
# second dhcp_start declaration, #if __MICROBLAZE__, string literals as char *).
TEMPLATE_SRCS   := main.c echo.c platform.c
TEMPLATE_CFLAGS := -Wno-strict-prototypes -Wno-missing-prototypes -Wno-missing-declarations \
                   -Wno-redundant-decls -Wno-undef -Wno-write-strings
