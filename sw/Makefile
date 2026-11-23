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
#   make STACK_SIZE=0x4000 [HEAP_MIN=0x10000]   stack size / minimum heap (see link.ld)
# apps/<APP>/app.mk (optional) holds per-app defaults: RUN_FROM, STACK_SIZE, HEAP_MIN, APP_CFLAGS, and
# TEMPLATE_SRCS/TEMPLATE_CFLAGS (extra flags only for copied AMD template files,
# e.g. -Wno-... so they stay unmodified).
#   make WERROR=0        warnings stay warnings (default: -Werror); EXTRA_WARN=... adds more
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
STACK_SIZE  ?=          # bytes, e.g. 0x4000; empty = link.ld default (0x2000 = 8 KB)
HEAP_MIN    ?=          # bytes the heap must at least get; empty = link.ld default (0x1000)
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
# Warnings. WERROR=1 (default) turns them into errors; WERROR=0 for quick experiments.
# EXTRA_WARN adds more (e.g. EXTRA_WARN=-Wswitch-enum), WARN=... replaces the whole set.
WARN    ?= -Wall -Wextra -Wshadow -Wundef -Wdouble-promotion -Wformat=2 -Wformat-truncation=2 \
           -Wstrict-prototypes -Wmissing-prototypes -Wmissing-declarations -Wredundant-decls \
           -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wnull-dereference \
           -Wlogical-op -Wduplicated-cond -Wduplicated-branches -Wvla -Wstack-usage=2048
EXTRA_WARN ?=
WERROR  ?= 1
ifneq ($(WERROR),0)
WARN    += -Werror
endif
CFLAGS  += $(ARCH) $(OPT) -g3 -std=gnu11 $(WARN) $(EXTRA_WARN) -DSDT \
           -ffunction-sections -fdata-sections -fno-common \
           -isystem $(BSP)/include -MMD -MP
APP_CFLAGS ?=
TEMPLATE_SRCS ?=
TEMPLATE_CFLAGS ?=
file_cflags = $(APP_CFLAGS) $(if $(filter $(notdir $(1)),$(TEMPLATE_SRCS)),$(TEMPLATE_CFLAGS))
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
	    af=$$([ $$a = common ] || $(MAKE) --no-print-directory -s APP=$$a SRC=$$f print-app-cflags); \
	    printf '%s{ "directory": "%s", "file": "%s",\n    "command": "%s %s -I%s -Icommon -c %s -o %s" }\n' \
	        "$$sep" "$(CURDIR)" "$(CURDIR)/$$f" "$(CC) $(CFLAGS)" "$$af" "$$d" "$$f" "$(OUT_ROOT)/$$a/obj/$$(basename $${f%.c}).o"; \
	    sep=','; done; echo ']'; } > $@.tmp
	@cmp -s $@.tmp $@ && rm -f $@.tmp || mv $@.tmp $@

$(OUT)/obj/common/%.o: common/%.c Makefile $(OUT)/cflags.txt $(BSP)/lib/libxil.a
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Icommon -c $< -o $@

print-app-cflags:   # SRC=<file> adds TEMPLATE_CFLAGS if it is a template file
	@echo '$(call file_cflags,$(SRC))'

print-run-from:
	@echo '$(RUN_FROM)'

# Flash image for the bootloader (sw/apps/boot), DDR programs only.
$(OUT)/app.img: $(OUT)/$(ELF).elf ../scripts/mkimage.py common/mbv_image.h
	python3 ../scripts/mkimage.py $< $@ --name $(APP)

# BSP headers come in via -isystem, so -MMD does not track them: depend on the BSP
# library instead, which every `make bsp` rebuilds (e.g. lwipopts.h after a
# sw/bsp.conf change would otherwise not recompile the program).
$(OUT)/obj/%.o: $(APPDIR)/%.c Makefile $(wildcard $(APPDIR)/app.mk) $(OUT)/cflags.txt $(BSP)/lib/libxil.a
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(call file_cflags,$<) -I$(APPDIR) -Icommon -c $< -o $@

# Compiler flags of this build; rewritten only when they change (WERROR, EXTRA_WARN,
# OPT, PRINTF_FLOAT, app.mk ...), and every object depends on it, so a flag change
# recompiles everything instead of silently keeping old objects.
FLAGS_STAMP := $(CC) $(CFLAGS) | $(APP_CFLAGS) | $(TEMPLATE_SRCS) | $(TEMPLATE_CFLAGS)
$(OUT)/cflags.txt: FORCE
	@mkdir -p $(OUT)
	@echo '$(FLAGS_STAMP)' | cmp -s - $@ || echo '$(FLAGS_STAMP)' > $@

# Link settings for link.ld: REGION_ALIAS plus, if set, the stack and minimum heap
# size (otherwise link.ld's defaults: 8 KB stack, 4 KB minimum heap). Rewritten only
# when RUN_FROM, STACK_SIZE or HEAP_MIN change, so a change relinks.
REGION_LD := REGION_ALIAS("CODE", $(RUN_FROM));$(if $(STACK_SIZE), _STACK_SIZE = $(STACK_SIZE);)$(if $(HEAP_MIN), _MIN_HEAP = $(HEAP_MIN);)
$(OUT)/region.ld: FORCE
	@mkdir -p $(OUT)
	@echo '$(REGION_LD)' | cmp -s - $@ || echo '$(REGION_LD)' > $@

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
