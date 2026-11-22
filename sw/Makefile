# Author: w1gx
# Date:   2026-11-22
#
# Application build for the MicroBlaze V, against the BSP that
# scripts/build_bsp.sh generates from the hardware (AMD standalone runtime,
# drivers for every IP in the design, libraries from sw/bsp.conf).
#
# One program per directory in apps/ (apps/demo, apps/echo, ...), chosen with APP:
#
#   make [APP=demo]      apps/demo -> build/sw/demo/app.elf + download.bit (program in BRAM)
#   make APP=echo        apps/echo; its app.mk sets RUN_FROM=DDR -> app.elf + app.img (flash image for
#                        the bootloader apps/boot); load with scripts/run.sh or make flash APP=echo
#   make RUN_FROM=DDR    link any app into DDR instead (big programs, lwIP)
#   make elf | size | dis | clean    (clean: this APP's build/sw/<APP>)
#
# apps/<APP>/app.mk (optional) holds per-app defaults: RUN_FROM, APP_CFLAGS.
#   make compdb          only write compile_commands.json (VS Code / clangd); also done by all/elf
#
# printf is mapped to newlib's integer-only iprintf (saves ~45 KB of local
# memory). Build with PRINTF_FLOAT=1 for %f/%e/%g. xil_printf is also there.
#
# Inputs:  build/hw/out    (cpu.mk, memory.ld, system.bit, system.mmi)
#          build/bsp/domain (include/, lib/, Xilinx.spec)

XILINX_ROOT ?= /opt/Xilinx/2026.1
HW_OUT      ?= ../build/hw/out
BSP         ?= ../build/bsp/domain
APP         ?= demo
OUT_ROOT    ?= ../build/sw
CROSS       ?= $(XILINX_ROOT)/gnu/riscv/lin/x86_64-oesdk-linux/usr/bin/riscv32-xilinx-elf/riscv32-xilinx-elf-
SYSROOT     ?= $(XILINX_ROOT)/gnu/riscv/lin/riscv32-xilinx-elf
UPDATEMEM   ?= $(XILINX_ROOT)/Vivado/bin/updatemem
PROC        ?= system_i/microblaze_riscv_0
APPDIR      := apps/$(APP)
ifeq ($(wildcard $(APPDIR)/*.c),)
$(error no sources in $(APPDIR) - available apps: $(notdir $(wildcard apps/*)))
endif
-include $(APPDIR)/app.mk
RUN_FROM    ?= LMB
OUT         := $(OUT_ROOT)/$(APP)

ifeq ($(wildcard $(HW_OUT)/cpu.mk),)
$(error $(HW_OUT)/cpu.mk not found - run hw/build_hw.sh first)
endif
ifeq ($(wildcard $(BSP)/lib/libxil.a),)
$(error BSP not found in $(BSP) - run scripts/build_bsp.sh)
endif
include $(HW_OUT)/cpu.mk

CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
SIZE    := $(CROSS)size

ELF     := app
SRCS    := $(wildcard $(APPDIR)/*.c)
COMMON  := $(wildcard common/*.c)                       # linked into every program
OBJS    := $(addprefix $(OUT)/obj/,$(notdir $(SRCS:.c=.o))) \
           $(addprefix $(OUT)/obj/common/,$(notdir $(COMMON:.c=.o)))
# every library the BSP built: libxil (drivers), libxilstandalone, libxiltimer, liblwip220, ...
BSP_LIBS := $(patsubst lib%.a,-l%,$(notdir $(wildcard $(BSP)/lib/lib*.a)))

OPT     ?= -O2
PRINTF_FLOAT ?= 0
ifeq ($(PRINTF_FLOAT),0)
CFLAGS  += -Dprintf=iprintf -Dfprintf=fiprintf -Dsprintf=siprintf -Dsnprintf=sniprintf \
           -Dvprintf=viprintf -Dvfprintf=vfiprintf -Dvsprintf=vsiprintf -Dvsnprintf=vsniprintf
endif
ARCH    := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany --sysroot=$(SYSROOT)
CFLAGS  += $(ARCH) $(OPT) -g3 -std=gnu11 -Wall -Wextra -DSDT \
           -ffunction-sections -fdata-sections -fno-common \
           -isystem $(BSP)/include -MMD -MP
APP_CFLAGS ?=
LDFLAGS += $(ARCH) -specs=$(BSP)/Xilinx.spec -L$(BSP)/lib -L$(HW_OUT) -L$(OUT) -T link.ld \
           -Wl,--gc-sections -Wl,--build-id=none -Wl,--no-warn-rwx-segments \
           -Wl,-Map=$(OUT)/$(ELF).map -Wl,--print-memory-usage \
           -Wl,--defsym=__mbv_link_id=$$(date +%s)   # new value per link, see common/data_restore.c
LDLIBS  += -Wl,--start-group $(BSP_LIBS) -lc -lm -lgcc -Wl,--end-group

.PHONY: all elf size dis clean compdb print-app-cflags print-run-from FORCE
ifeq ($(RUN_FROM),LMB)
all: $(OUT)/download.bit size compdb
else
all: $(OUT)/app.img size compdb
endif
elf: $(OUT)/$(ELF).elf compdb
compdb: $(OUT_ROOT)/compile_commands.json

# Compilation database for editors, covering every app (each file with its
# app's include directory). Rewritten only when something in it changes.
$(OUT_ROOT)/compile_commands.json: FORCE
	@mkdir -p $(OUT_ROOT)
	@{ echo '['; sep=' '; for f in apps/*/*.c common/*.c; do d=$$(dirname $$f); a=$$(basename $$d); \
	    af=$$([ $$a = common ] || $(MAKE) --no-print-directory -s APP=$$a print-app-cflags); \
	    printf '%s{ "directory": "%s", "file": "%s",\n    "command": "%s %s -I%s -Icommon -c %s -o %s" }\n' \
	        "$$sep" "$(CURDIR)" "$(CURDIR)/$$f" "$(CC) $(CFLAGS)" "$$af" "$$d" "$$f" "$(OUT_ROOT)/$$a/obj/$$(basename $${f%.c}).o"; \
	    sep=','; done; echo ']'; } > $@.tmp
	@cmp -s $@.tmp $@ && rm -f $@.tmp || mv $@.tmp $@

$(OUT)/obj/common/%.o: common/%.c Makefile $(BSP)/lib/libxil.a
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Icommon -c $< -o $@

print-app-cflags:
	@echo '$(APP_CFLAGS)'

print-run-from:
	@echo '$(RUN_FROM)'

# Flash image for the bootloader (sw/apps/boot), DDR programs only.
$(OUT)/app.img: $(OUT)/$(ELF).elf ../scripts/mkimage.py common/mbv_image.h
	python3 ../scripts/mkimage.py $< $@ --name $(APP)

# BSP headers come in via -isystem, so -MMD does not track them: depend on the BSP
# library instead, which every `make bsp` rebuilds (e.g. lwipopts.h after a
# sw/bsp.conf change would otherwise not recompile the program).
$(OUT)/obj/%.o: $(APPDIR)/%.c Makefile $(wildcard $(APPDIR)/app.mk) $(BSP)/lib/libxil.a
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(APP_CFLAGS) -I$(APPDIR) -Icommon -c $< -o $@

# REGION_ALIAS for link.ld; rewritten only when RUN_FROM changes.
$(OUT)/region.ld: FORCE
	@mkdir -p $(OUT)
	@echo 'REGION_ALIAS("CODE", $(RUN_FROM));' | cmp -s - $@ || echo 'REGION_ALIAS("CODE", $(RUN_FROM));' > $@

$(OUT)/$(ELF).elf: $(OBJS) link.ld $(OUT)/region.ld $(HW_OUT)/memory.ld $(wildcard $(BSP)/lib/*.a)
	$(CC) $(LDFLAGS) $(OBJS) $(LDLIBS) -o $@

# Bitstream with the program in the local memory: boots at power-up, no
# debugger needed, no re-implementation when only software changes.
$(OUT)/download.bit: $(OUT)/$(ELF).elf $(HW_OUT)/system.bit $(HW_OUT)/system.mmi
	cd $(OUT) && $(UPDATEMEM) -force -meminfo $(abspath $(HW_OUT)/system.mmi) -data $(abspath $<) \
	    -bit $(abspath $(HW_OUT)/system.bit) -proc $(PROC) -out $(abspath $@) > updatemem.out \
	    || { cat updatemem.out; exit 1; }
	@echo "download.bit -> $@"

size: $(OUT)/$(ELF).elf
	@$(SIZE) $<

dis: $(OUT)/$(ELF).elf
	$(OBJDUMP) -d -S $< > $(OUT)/$(ELF).lst
	@echo "$(OUT)/$(ELF).lst"

clean:
	rm -rf $(OUT)

-include $(OBJS:.o=.d)
