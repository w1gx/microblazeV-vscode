# CLAUDE.md

MicroBlaze V (AMD's RISC-V soft CPU) on a Digilent **Arty A7-100T** (`xc7a100tcsg324-1`),
built **without the Vitis IDE**. Everything is scripts and `make`, using command-line
tools that ship with **Vivado 2026.1** (`/opt/Xilinx/2026.1`). The project deliberately avoids
the Vitis IDE. Don't suggest it, and keep every change inside this script flow.
README.md is the user-facing guide. This file covers how things work and what to watch out for.

## Commands

```sh
make hw          # batch hardware build (~15 min, ~1 min if fingerprint matches), then BSP; never implicit
REBUILD=1 make hw # full build even if the fingerprint matches
make             # app: compile + link into build/sw/<APP>/; LMB apps -> download.bit (updatemem), DDR apps -> app.img
make program     # JTAG (LMB apps)   make flash    # SPI flash, boots at power-up (DDR apps: + bootloader)
make console     # UART 115200       make run      # system.bit via JTAG + ELF via xsdb (DDR apps, volatile)
make debug-load  # like make run but CPU stays halted at the entry, for GDB on port 3004 (VS Code F5)
make APP=echo    # programs = sw/apps/<APP>/ (default demo); APP works for make/program/flash/run
make WERROR=0    # warnings don't stop the build (default -Werror); EXTRA_WARN=-W... adds more
make bsp         # regenerate BSP only (after editing sw/bsp.conf)
make gui         # Vivado GUI on build/hw/proj with "MBV:" toolbar buttons
FORCE=1 make hw  # discard unexported GUI edits     make gui FRESH=1  # recreate project
make RUN_FROM=DDR -C sw   # link into DDR (big programs/lwIP), load with make run; apps/<APP>/app.mk can set it
make STACK_SIZE=0x4000 HEAP_MIN=0x10000   # stack size / minimum heap (default 0x2000 / 0x1000); app.mk can set them
```

## Pipeline

1. **Hardware:** `hw/system_bd.tcl` + `hw/arty_a7_100.xdc` → `hw/build_hw.sh` → `hw/build_hw.tcl` → procedures in
   `hw/project.tcl` (`mbv::new_project`, `mbv::build`, `mbv::export_bd`, `mbv::bsp`).
   Output in `build/hw/out`: `system.bit` (local memory empty), `system.mmi`, `system.xsa`,
   `memory.ld` + `cpu.mk` (from `hw/gen_memmap.tcl`), reports.
2. **BSP:** `scripts/build_bsp.sh`: `sdtgen` (xsa → system device tree, `build/bsp/sdt`) →
   `empyro create_bsp` (picks a driver for every IP, generates `xparameters.h` and the `*_g.c`
   config tables, adds the standalone runtime and xiltimer) → `empyro config_bsp -al/-st` (libs/options from
   `sw/bsp.conf`; **lwip220 is added automatically if `pl.dtsi` contains an Ethernet MAC**) →
   `empyro build_bsp` → `build/bsp/domain/{include,lib}`. Takes about 20 s.
3. **App:** `sw/Makefile` compiles every `.c` under `sw/apps/$(APP)/` (subdirectories too, `find`) plus `sw/common/*.c`
   (+ `app.mk`: RUN_FROM, APP_CFLAGS) into `build/sw/$(APP)/`. Objects mirror the tree (`obj/modules/rgb/rgb.o`).
   `APP_INCS` = `-I` for the app directory plus every subdirectory with a `.h`, so `#include "rgb.h"` works from
   anywhere in the app. Links **every** `build/bsp/domain/lib/lib*.a` and uses `-specs=$(BSP)/Xilinx.spec`.
   LMB apps: `updatemem` → `build/sw/$(APP)/download.bit`. DDR apps: `scripts/mkimage.py` → `build/sw/$(APP)/app.img`.
   It also writes `build/sw/compile_commands.json` (all apps) for VS Code.

`hw/system_bd.tcl` is the version that matters for the block design. `build/` is generated and
git-ignored, and it is safe to delete, but rebuilding takes 15 min. The GUI loop is: `make gui` →
edit → "MBV: Build HW + BSP" (orange hammer icon; Export BD is the green arrow, icons in `hw/gui/icons/`, without `-toolbar_icon` Vivado shows a generic "Tcl" icon; exports to `hw/system_bd.tcl`, implements in the open
project, writes the outputs, runs the BSP) → `make`. Batch `make hw` refuses to recreate a
project whose block design differs from `hw/system_bd.tcl` (it compares `write_bd_tcl`
output with comments stripped), and refuses while `hw/gui.tcl` is running.

### Skipping work

- **Fingerprint:** `mbv::fingerprint` (`hw/project.tcl`) is a sha256 over the Vivado version, part, board_part, and the
  comment-stripped `hw/system_bd.tcl` and xdc. After a successful build it goes to `build/hw/out/source.fingerprint`
  (deleted before a full build starts, so an interrupted build never matches). `build_hw.tcl` and `mbv::build`
  skip implementation when all outputs exist and the fingerprint matches. `REBUILD=1` overrides this.
  On such a skip, `mbv::confirm_outputs` touches `source.fingerprint`. `hw-check` (top Makefile) compares `HW_SRC`
  mtimes against that file (fallback `system.bit`), so a file git rewrote with the same content (seen after merging
  PR #1: "system_bd.tcl is newer than the bitstream" while `make hw` had nothing to do) stops warning after one `make hw`.
  Project settings outside the BD and xdc (run strategies etc.) are **not** in the fingerprint. Use `REBUILD=1` after changing them.
- **IP cache:** `mbv::setup_project` sets `IP_OUTPUT_REPO build/hw/ipcache` and
  `IP_CACHE_PERMISSIONS {read write}` (on project creation and in `gui.tcl` on open).
  The cache lives outside `build/hw/proj`, so it survives `new_project`. Measured: a full rebuild takes 10 min with the
  cache against 15 min without. 14 of 15 IP blocks come from the cache. The **MIG is never stored in the cache** (no
  entry for it after a full build), so it is always re-synthesized, about 5 min of the remaining 10.
- **BSP only when needed:** after a hardware build, the BSP is rebuilt only through `make bsp` (deps: `system.xsa`,
  `sw/bsp.conf`, `scripts/build_bsp.sh`). `mbv::bsp` prints `mbv: BSP is up to date` otherwise.

## Hardware facts

- **Clock:** MIG `ui_clk` **81.25 MHz** (`XPAR_CPU_CORE_CLOCK_FREQ_HZ` = 81247969) runs
  everything. The board's 100 MHz `sys_clk_i` (pin E3, **defined only in the xdc**) only feeds the MIG.
  See Clocking below.
- **CPU:** MicroBlaze V, reset vector 0x0, **no M/A/F/C extensions**:
  `-march=rv32i_zicsr_zifencei_zicbom -mabi=ilp32` (derived in `gen_memmap.tcl` with the
  same rules as AMD's `system-device-tree-xlnx/cpu/data/cpu.tcl`). 16 KB I-cache and 16 KB D-cache
  cover DDR. The debug module is enabled.
- **Address map:**

  | Block             | Address       | Notes                                                                                         |
  | ----------------- | ------------- | --------------------------------------------------------------------------------------------- |
  | LMB               | `0x0000_0000` | 128 KB, 32 RAMB36                                                                             |
  | DDR3              | `0x8000_0000` | 256 MB                                                                                        |
  | UART Lite         | `0x4060_0000` | 115200 8N1, IRQ 0                                                                             |
  | AXI GPIO 0        | `0x4000_0000` | 4 LEDs, `led_4bits`                                                                           |
  | AXI GPIO 1        | `0x4001_0000` | ch1 `push_buttons_4bits`, ch2 `dip_switches_4bits`, IRQ 1                                     |
  | AXI GPIO 2        | `0x4002_0000` | 12 outputs, `rgb_led` (LD0..LD3; bit 3n blue, 3n+1 green, 3n+2 red), no IRQ, SmartConnect M07 |
  | AXI Ethernet Lite | `0x40E0_0000` | `eth_mii` + `eth_mdio_mdc` (DP83848 PHY, 10/100 MII), IRQ 2                                   |
  | AXI Quad SPI      | `0x44A0_0000` | `qspi_flash`, quad mode, SCK = `ui_clk`/2 = 40.6 MHz, no STARTUPE2 (SCK on pin L16), IRQ 3    |
  | AXI Timer 0       | `0x41C0_0000` | tick for lwIP / xiltimer (`XILTIMER_tick_timer:axi_timer_0`), IRQ 4                           |
  | AXI Timer 1       | `0x41C1_0000` | demo's RGB sequence (`modules/rgb/rgb_seq.c`), IRQ 5, SmartConnect M08                        |
  | AXI INTC          | `0x4120_0000` | **fast-interrupt mode** (`C_HAS_FAST=1`), 6 inputs through the concat                         |

- **Resources:** 46/135 RAMB36, about 20 % of LUTs (12,541 with the second timer). Timing met with about +1.3 ns WNS at 81 MHz (+1.316 with the RGB GPIO, +1.259 with axi_timer_1).
- **Configuration settings:** the xdc adds CFGBVS/CONFIG_VOLTAGE plus `SPI_BUSWIDTH 4`,
  `CONFIGRATE 33` and `COMPRESS` for quad-SPI boot.

## Clocking (important when changing anything clock-related or moving to another board)

```txt
pin E3, 100 MHz oscillator ──> port sys_clk_i ──> MIG sys_clk_i (single-ended, input 99.997 MHz)
                                                    │  MMCM: DDR3 at 3077 ps (325 MHz), PHY ratio 4:1
                                                    ├─ ui_clk        81.25 MHz ─> CPU, LMB, all AXI, UART, GPIO, INTC
                                                    │                             (rst_mig_7series_0_81M reset)
                                                    └─ ui_addn_clk_0 200 MHz  ─> MIG clk_ref_i (IDELAYCTRL, "No Buffer")
                                                                                └─> clk_wiz_eth (exact 1:8) ─> port eth_ref_clk 25 MHz (pin G18) ─> PHY X1
```

- **`sys_clk_i` exists only in `hw/arty_a7_100.xdc`:** the block-design port `sys_clk_i` gets its pin
  (`PACKAGE_PIN E3 IOSTANDARD LVCMOS33`) only there. The port name in the xdc and in `hw/system_bd.tcl` must match.
  Without the line, implementation and bitstream fail on an unplaced or unconstrained clock I/O.
  The line is the Arty master-xdc `CLK100MHZ` line, renamed.
- **No `create_clock` in our xdc:** the MIG's generated xdc has `create_clock -period 10 [get_ports sys_clk_i]`.
  Adding our own would create a duplicate or conflicting clock.
- **Harmless warning:** the BD port is created without `FREQ_HZ`, hence `WARNING: [BD 5-670] ... provide a frequency
  value for a user created input clock port` on every build. It's harmless. A possible cleanup is
  `set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports sys_clk_i]`, which needs a rebuild.
- **MIG settings come from the board preset:** `CONFIG.BOARD_MIG_PARAM {ddr3_sdram}` reads the board file's
  `mig.prj` (input clock, DDR3 timing, pins). The generated copy is in
  `build/hw/proj/mb_v.gen/.../system_mig_7series_0_0/mig.prj`.
- **The CPU clock comes from the MIG:** `ui_clk` (81.25 MHz) depends on the DDR3 speed and PHY ratio.
  `XPAR_CPU_CORE_CLOCK_FREQ_HZ` (81247969) follows automatically via the device tree.
- **`eth_ref_clk`, the second clock pin in the xdc:** the DP83848 PHY has no crystal, so the FPGA drives its 25 MHz.
  The board files don't include this pin, so `hw/arty_a7_100.xdc` has `PACKAGE_PIN G18` for port `eth_ref_clk`.
  Ethernet needs it within **±50 ppm**.
- **BD clock metadata is rounded, the hardware isn't:** the BD says `ui_clk` = 81.247969 MHz and `ui_addn_clk_0` =
  199.692 MHz, rounded from the MIG's 3077 ps period. The real clocks, which the timing report also uses, are exactly
  81.25 and 200.000 MHz (VCO 650 MHz). A clocking wizard therefore optimises against the wrong input:
  - asking for 25.000 MHz from `ui_clk` gave 25.005 MHz (+200 ppm)
  - asking for 25.000 MHz from 199.692 gave a 40.625/11/29.5 ratio, which is 25.04 MHz in reality
  The fix is to request `199.692/8 = 24.9615` MHz, so the wizard picks an exact 1:8 ratio (9.125 / (2 × 36.5)).
  **Always check derived clocks in `build/hw/out/timing.rpt` (Clock Summary), not in the BD.**
- **UART clock is hard-coded:** `axi_uartlite_0` has `CONFIG.C_S_AXI_ACLK_FREQ_HZ_d {81.25}`, entered by hand
  in MHz (user value). The baud divider is built from it. If `ui_clk` changes and this doesn't, the console
  baud rate is wrong. Update it with every clock change.

**Checklist for moving to another board:**

1. **Board files:** board part in `hw/project.tcl` (`board_part`, `part`), plus the board files in `BOARD_REPO`.
2. **Clock pin:** in the xdc, the `sys_clk_i` pin and IO standard of the new board's oscillator.
3. **MIG:** the new board's DDR preset name (`BOARD_MIG_PARAM`), and that its input clock period matches the oscillator.
   No DDR at all means removing the MIG and supplying a clock (Clocking Wizard on `sys_clk_i`) plus reset for the
   whole system. The xdc then needs a `create_clock` on `sys_clk_i`.
4. **UART clock:** `C_S_AXI_ACLK_FREQ_HZ_d` to the new `ui_clk`/system clock.
5. **Peripherals:** the board-interface names of UART, LEDs, RGB LEDs, buttons, switches, `eth_mii`/`eth_mdio_mdc` and
   `qspi_flash` (`*_BOARD_INTERFACE`). Also the `eth_ref_clk` pin, if the PHY needs a clock from the FPGA at all.
6. **Flash:** `FLASH_PART` and the config-bank settings (`CFGBVS`/`CONFIG_VOLTAGE`/SPI width) in the xdc.

## Software facts

- **Startup:** standalone `boot.S` `_boot` (at 0x0, section `.text.init`: disables interrupts, sets mtvec to
  `_trap_handler`, sets gp/sp, clears .sbss) → toolchain `crt0.o` `_start` (memsets `__bss_start`..`_end`,
  init arrays) → `main`. `sw/link.ld` is based on Vitis' generated lscript and must keep its
  symbols: `__sbss_start/__sbss_end`, `__bss_start`, `_end`, `_heap_start/_heap_end` (used by
  standalone `_sbrk`), `__stack`, `__global_pointer$`, `_SDA_BASE_`, and a `.drvcfg_sec` section for the
  driver config tables. The heap fills everything between `.bss` and the 8 KB stack at the top.
  **`__stack` = region end − 16, never the region end itself:** `boot.S` does `sw zero,0(sp)` right after
  `la sp, __stack`. At 0x20000 or 0x90000000 that store goes past the LMB or DDR, and the CPU hangs before `main()` with
  no output. This happened on the board for both programs; the PC was stuck at `boot.S` line 195.
- **RESET button / `.data`:** the bitstream initialises the LMB once, at configuration. RESET (and xsdb `rst -processor`)
  restarts the CPU. crt0 clears `.bss` again, but `.data` keeps the previous run's values. newlib's stdio state lives
  there, so after a reset printf printed **nothing** (verified on the board: `outbyte` never reached).
  `sw/common/data_restore.c` fixes this. It is the first constructor (priority 101, check that it is the first `.init_array`
  entry). It saves `__drvcfgsecdata_start..__tdata_end` (driver config tables .. `.tdata`, about 3 KB) to `.noinit` on the
  first start and restores it on every later start. The copy is tagged with magic + `__mbv_link_id`, which is
  `--defsym=__mbv_link_id=$(date +%s)` at every link, so a stale copy from another build (DDR keeps content across
  configurations) is never restored. `link.ld`: `_end` (= the crt0 clear limit) comes **before** `.noinit`, and the heap starts after it.
  Verified: two `rst -processor` in a row both print again.
- **DDR programs and RESET:** with `make run`, the LMB holds no program (plain `system.bit`), and the CPU's reset vector
  is 0x0 in the LMB. After RESET the CPU never reaches the DDR program, so nothing runs (seen on the board).
  PROG reconfigures from flash. (The PROG button sits next to the DONE LED and is easily called "the DONE button".)
  The fix is the bootloader below, via `make flash APP=<ddr app>`.
- **Bootloader (`sw/apps/boot`, about 18 KB, LMB):**
  - **Format:** `scripts/mkimage.py` writes `app.img` from the ELF's PT_LOAD segments (filesz > 0 only, all inside DDR,
    at most 8). It has a 256-byte header (`struct mbv_image_header`: magic "MBVI", version 1, entry, nseg, payload size,
    zlib CRC-32 over the segments, name[16], seg[8]{addr,size,offset}, header CRC over the first 136 bytes), then the segments.
    `sw/common/mbv_image.h` is the single source. The Python script and `flash.sh` read its constants with a regex.
  - **What the bootloader does:** plain READ 0x03 in 256-byte chunks with XSpi polled, then checks the CRC of the DDR
    contents. It calls `Xil_DCacheFlush()` (the D-cache is write-through, so this is a precaution) and
    `Xil_ICacheInvalidate()`, then jumps to the entry. The app's own `boot.S`/crt0 set up the rest.
  - **Flash layout:** bitstream at 0, image at `MBV_IMAGE_FLASH_OFFSET` 0x400000 (`write_cfgmem -loaddata "up <off> app.img"`).
  - **Build wiring:** `make flash` asks `sw/Makefile print-run-from`. For DDR it also builds `APP=boot`, and `flash.sh`
    takes `build/sw/boot/download.bit` plus `build/sw/<APP>/app.img`. DDR apps' `make all` builds `app.img`.
  - **Testing the bootloader alone:** `make program APP=boot` boots whatever image is in flash, without reflashing.
- **`sw/common/`:** sources linked into every program (currently `data_restore.c`), with their own entries in
  compile_commands.json.
- **Where a program runs (`RUN_FROM`):** precedence is command line (`make RUN_FROM=DDR`), then
  `sw/apps/<name>/app.mk` (`RUN_FROM := DDR`), then the default `LMB`. Values are the `memory.ld` region names.
  README "Where a program runs: block RAM or DDR" explains it for users: table, the fit check
  ("program does not fit in the CODE region"), and `.ddr` buffers as a middle way. Keep it in sync with
  `sw/Makefile` and `link.ld`.
- **Stack and heap (`link.ld` + `region.ld`):** `sw/Makefile` writes `build/sw/<APP>/region.ld` (cmp-rewritten, so a
  change relinks): `REGION_ALIAS("CODE", $(RUN_FROM))`, plus `_STACK_SIZE = …;` / `_MIN_HEAP = …;` only when
  `STACK_SIZE` / `HEAP_MIN` are set (command line or `app.mk`). `link.ld` INCLUDEs it before its
  `DEFINED(_STACK_SIZE) ? … : 0x2000` / `0x1000` defaults, so the defaults live only in `link.ld`. Stack = top
  `_STACK_SIZE` bytes below `__stack`; heap = `_heap_start` (after `.noinit`, or after `.ddr` for DDR apps) up to
  `_heap_end = _stack_end`, so there is no fixed heap size. `_MIN_HEAP` is just the link-time
  `ASSERT` ("program does not fit in the CODE region"). The BSP's `_sbrk` (libxilstandalone) returns ENOMEM past
  `_heap_end`; there is no run-time stack-overflow check. Verified: `STACK_SIZE=0x4000` moves `_stack_end` to
  0x1bff0, `0x14000` trips the ASSERT for demo. README "Memory layout, stack and heap" documents it for users.
- **`.ddr` section:** a NOLOAD section in DDR for big buffers
  (`__attribute__((section(".ddr")))`), not zeroed. With `RUN_FROM=DDR`, `region.ld` aliases
  CODE to DDR and the heap starts after `.ddr`.
- **printf:** `-Dprintf=iprintf` and friends by default, because floating-point printf costs about 45 KB.
  `PRINTF_FLOAT=1` turns it back on. This toolchain has **no newlib-nano**.
- **Warnings:** `WARN` in `sw/Makefile` = `-Wall -Wextra` + shadow/undef/format=2/strict- and missing-prototypes/
  redundant-decls/cast-qual/write-strings/null-dereference/logical-op/duplicated-*/vla/`-Wstack-usage=2048`,
  plus `-Werror` unless `WERROR=0`. `EXTRA_WARN` adds flags. demo, boot, `common/` and echo's own files are clean.
  AMD's echo template files (`main.c`, `echo.c`, `platform.c`) are not: `app.mk` lists them in `TEMPLATE_SRCS` and
  `TEMPLATE_CFLAGS` adds `-Wno-*` for them only (K&R `()` prototypes, `#if __MICROBLAZE__`, string literals as
  `char *`, a second `dhcp_start` declaration). `print-app-cflags SRC=<file>` gives compdb the same per-file flags plus `APP_INCS`.
  Objects depend on `build/sw/<APP>/cflags.txt` (compiler + all flags, rewritten only on change), so changing
  `WERROR`, `EXTRA_WARN`, `OPT`, `PRINTF_FLOAT` or `app.mk` recompiles everything. A plain `make` with nothing
  changed shows no gcc lines, so no `-Wall` in the output either.
- **Names:** use AMD's `xparameters.h` names: `XPAR_XGPIO_0_BASEADDR`, `XPAR_XUARTLITE_0_BASEADDR`,
  `XPAR_CPU_CORE_CLOCK_FREQ_HZ`, `XPAR_LMB_BRAM_0_BASEADDRESS/HIGHADDRESS`,
  `XPAR_MIG_0_BASEADDRESS/HIGHADDRESS`.
- **Driver API:** in SDT mode (compile with `-DSDT`), drivers are initialised **by base address**:
  `XGpio_Initialize(&g, XPAR_XGPIO_0_BASEADDR)`. Interrupt IDs are encoded (`XPAR_XGPIO_1_INTERRUPTS
  0x2001` = input 1 plus trigger flags in bits 15:12). Unconnected interrupts are 0xffff.
- **lwIP:** `build_bsp.sh` adds lwip220 automatically because of the EmacLite (verified: "Ethernet MAC found -> adding
  lwip220", `liblwip220.a` built). lwIP is only linked when the app calls it. An lwIP app needs much more RAM than
  the 128 KB LMB (default `lwip220_mem_size` and pbuf pool), so give it `RUN_FROM := DDR` in its `app.mk`. Load it with
  `make run`, or flash it with the bootloader. Alternatively, shrink the pools in `sw/bsp.conf`. The AXI Timer exists for lwIP's tcp_fasttmr/slowtmr tick.
- **QSPI flash layout:** `make flash` writes the bitstream (`download.bit`, or the bootloader's for DDR apps) at offset 0.
  The compressed bitstream is about 2.2 MB, and the uncompressed worst case for the 100T is about 3.9 MB. DDR apps' `app.img`
  sits at **0x00400000**. Keep other application data well above that (e.g. ≥ 8 MB) of the 16 MB flash. The demo only reads (JEDEC ID 0x9F, read 0x03 at address 0 to look
  for the sync word AA995566).
- **Demo:** `sw/apps/demo/main.c` prints the configuration, runs a 1 MB DDR test, checks the Ethernet PHY over MDIO (scans all
  32 addresses, ID and link via BMSR/PHYSTS) and the QSPI flash (JEDEC ID, so the right `FLASH_PART` is known), shows a light chaser on
  the LEDs (speed set by the switches, buttons override), polls the buttons (the only interrupt is the RGB timer's) and echoes the UART.
- **RGB LEDs (`sw/apps/demo/modules/rgb/rgb.c`, with `rgb.h` and `rgb_seq.c` in the same folder):** software PWM on `axi_gpio_2`, 64 levels x 16 µs (1.024 ms period), timed with
  the `cycle` CSR. It runs only inside `rgb_pwm_run(us)`, which busy-waits and switches the LEDs off when it returns.
  The demo's main loop calls `rgb_pwm_run(5000)` where it used to `usleep(5000)`, after `rgb_seq_update()` (below).
  `rgb_selftest()` writes and reads back 0xA5A/0x5A5/0xFFF/0 (an all-output axi_gpio reads back its data register),
  then shows red, green and blue on each LED, all white and a brightness ramp. Only the readback is
  checked automatically; the colours have to be checked by eye. `RGB_BRIGHT` = 16/64: full duty is glaring.
- **RGB sequence (`sw/apps/demo/modules/rgb/rgb_seq.c`, axi_timer_1):** counter 0 in generate mode, down count, auto reload,
  TLR = 2 s × `XPAR_XTMRCTR_1_CLOCK_FREQUENCY` − 2 (period = TLR + 2 cycles). The ISR (`XTmrCtr_SetHandler`
  callback, set up with `XSetupInterruptSystem`, normal INTC mode) only increments a counter. The main loop calls
  `rgb_seq_update()` before every `rgb_pwm_run(5000)`: a new count starts one 1 s colour-wheel turn
  (`rgb_rainbow()`), with the position from `TLR − XTmrCtr_GetValue()`, then `rgb_off()` until the next IRQ.
  `RGB_SEQ_PERIOD_MS`/`RGB_SEQ_ROT_MS` in `rgb.h`. The demo's first interrupt user (buttons are still polled).
  `XTmrCtr_Initialize` tracks "started" in the (cleared) instance, so it re-inits fine after a CPU reset.
  The board's PWM still only runs inside `rgb_pwm_run()`; the timer only paces the sequence.
- **Echo server (`sw/apps/echo`):**
  - **Source:** AMD's lwip_echo_server template (`Vivado/data/embeddedsw/lib/sw_apps/lwip_echo_server/src`).
    Copied: `main.c`, `echo.c`, `platform.c` and `platform.h`. Only `main.c` is changed, in lines marked `/* mb-test */`:
    the includes, three `netinfo_*` calls (the last one replaces `print_ip_settings()`), and an `emaclite_drain_rx()`
    before each `xemacif_input()`. `platform_config.h` is hand-written
    (`PLATFORM_EMAC_BASEADDR = XPAR_XEMACLITE_0_BASEADDR`). Not copied: `platform_mb.c` (non-SDT only), and the
    zynq, IIC, SFP and si5324 files.
  - **`netinfo.c` (startup report):** after `xemac_add` it prints the MAC address and controller. Before DHCP, a wait note.
    Afterwards it prints the PHY over MDIO (own `XEmacLite` instance, scan 0..31, DP83848 PHYSTS for speed and duplex),
    the address source (`dhcp_supplied_address`, server and lease from `netif_dhcp_data`, or the static fallback),
    IP, netmask, gateway and an `nc <ip> 7` line. `ECHO_PORT` in `netinfo.h` must match `echo.c`. It uses `xil_printf`,
    which supports `%-12s`, `%02x` and `%08x`.
  - **Timer and interrupts:** the SDT path uses `XTimer_SetInterval(50)` and `XTimer_SetHandler`. That needs
    `XILTIMER_en_interval_timer:true XILTIMER_tick_timer:axi_timer_0` in `sw/bsp.conf`. Interrupts are enabled
    by AMD's `xinterrupt_wrap` (`platform_enable_interrupts` is `#ifndef SDT` in `main.c`).
  - **lwIP options:** from the template's `data/lwip_echo_server.yaml` `depends_libs` (dhcp, acd check, no IPv6,
    2048 pbufs), set in `sw/bsp.conf`. The BSP is shared, so they also apply to demo, which doesn't link lwIP.
  - **Lost RX interrupts (`emaclite_rx.c`):** `XEmacLite_InterruptHandler` passes ONE frame to lwIP per call, and the
    EmacLite has two RX buffers with an edge IRQ. Two frames per interrupt leave one stuck with no further IRQ.
    On the board that gave ~320 ms pings and stalled TCP. `emaclite_drain_rx()` runs before both `xemacif_input()`
    calls in `main.c` (`/* mb-test */`). It checks both RSRs and calls the handler under `sys_arch_protect()`.
    Use the functions, not the `SYS_ARCH_PROTECT` macro, which uses MicroBlaze `mfmsr` in that header.
    After the fix: ping 0.5 ms, 5/5 echoes, and 26 KB echoed byte-identical in 30 ms.
  - **Warnings:** the template uses `xil_printf` without the header, so `app.mk` adds `-include xil_printf.h`.
    `compdb` picks up per-app flags via `make print-app-cflags`.
  - **Memory:** about 77 KB of code and data and 3.9 MB of `.bss`, all in DDR (`RUN_FROM := DDR`). There's no
    `download.bit`. Two ways to start it:
    - `make run`, which is `run.sh -p`: system.bit over JTAG, then `dow` through xsdb. Volatile.
    - `make flash APP=echo`: the bootloader at flash 0 and `app.img` at 0x400000.
  - **Addresses:** DHCP, falling back to 192.168.1.10/24 after `dhcp_timoutcntr` (~12 s). MAC 00:0a:35:00:01:02. TCP port 7.
- **Shortcut:** `sw/drivers/xparameters.h` is a **symlink** into the BSP, there only so it's easy to find.
  The build doesn't use it.

## Gotchas learned the hard way

- **Board files:** batch Vivado doesn't find the Digilent board files. They are in
  `~/.Xilinx/Vivado/2026.1/xhub/board_store/.../boards`, and `scripts/env_board.tcl` sets
  `board.repoPaths` (override with `BOARD_REPO`). Without them the MIG (`BOARD_MIG_PARAM ddr3_sdram`)
  and every board interface fail.
- **Toolchain:**
  - It needs `--sysroot=/opt/Xilinx/2026.1/gnu/riscv/lin/riscv32-xilinx-elf`, or `stdint.h` isn't found.
  - The cross gcc is at `.../gnu/riscv/lin/x86_64-oesdk-linux/usr/bin/riscv32-xilinx-elf/riscv32-xilinx-elf-gcc`.
  - The BSP itself is built by `empyro` with `gnu/riscv/lin/bin/riscv64-unknown-elf-gcc`, using rv32i flags.
- **Tool locations:** `xsdb`, `sdtgen`, `empyro`, `lopper`, `updatemem`, `hw_server`, `ninja` and cmake
  (`Vivado/tps`) are all under `Vivado/`, with **no Vitis needed**. The Vivado copy of the embeddedsw repo is
  `Vivado/data/embeddedsw`.
- **Block design export:** use `write_bd_tcl -force -no_project_wrapper`. The script defines
  `cr_bd_system ""`, which creates, validates and saves the block design. Settings that come from a board
  interface (e.g. the GPIO width) don't appear in the exported Tcl, so changing them makes no diff.
- **Tcl namespaces:** a proc inside `namespace mbv` named like a Vivado command shadows it.
  `mbv::create_project` broke `create_project`. Use `::cmd` or distinct names.
- **Watching the GUI log:** `build/hw/gui/vivado.log` also contains Vivado's echo of sourced scripts (`## error "..."`)
  and the copied logs of the synth/impl child runs (their `Exiting Vivado` lines). To wait for a GUI build, match only
  `^mbv: hardware and BSP done` or `^ERROR:`.
- **Concurrent builds:** two hardware builds at once break each other. Vivado rotates `build_hw.log` to
  `*.backup.log` when a second session starts, and the second `new_project` deletes `build/hw/proj` under
  the first. That's why `build_hw.sh` holds `flock build/hw/.build_hw.lock` and reads its result from
  `console.log`. Top-level `make` never starts `make hw` implicitly. `hw-check` only warns when
  `HW_SRC` is newer than `source.fingerprint` (see Fingerprint; the VS Code build task used to trigger a 15-min build silently).
- **No display in VS Code:** VS Code Remote-SSH terminals have no `DISPLAY`. Vivado then fails "Display test failed",
  runs the `-source` script anyway and exits. `scripts/gui.sh` tests `DISPLAY` with `xset q` and otherwise borrows a
  working `DISPLAY` from another process of the same user (`/proc/*/environ`), e.g. an `ssh -X` session. Vivado needs a
  full-featured X server behind the forwarding; with one, background `nohup` launches work fine.
  The GUI's Tcl output goes to `vivado.log`, not stdout, so check that file. Once, Vivado crashed in `start_gui`
  with `_XIOError` ("terminate called without an active exception") on a display that worked before and after.
  That's why `gui.sh` waits for `mbv: ready` and reports a failed start.
- **Editing scripts mid-run:** don't edit a bash script while it is running in the background. Bash reads
  scripts as it goes, and this broke `build_hw.sh` twice. Vivado's Tcl is read up front, so it isn't affected.
- **Read-only template copies:** files copied from `/opt/Xilinx/.../embeddedsw` keep their read-only permissions
  (`-r--r--r--`), so editing them fails with "Permission denied". Use `chmod u+w` after copying. Git doesn't track this.
- **BSP option changes must recompile the app:** BSP headers come in via `-isystem`, so `-MMD` doesn't track them.
  Objects used to depend only on `xparameters.h`, so changing an option in `sw/bsp.conf` (e.g. lwIP's in
  `lwipopts.h`) relinked old objects. Now `sw/Makefile` objects depend on `$(BSP)/lib/libxil.a`, which every BSP
  build rewrites.
- **IPv6:** `lwip220_ipv6_enable:true` in `sw/bsp.conf` gives `LWIP_IPV6 1`.
  - The echo template then takes an IPv6-only branch: `xemac_add` with NULL addresses, link-local
    `fe80::20a:35ff:fe00:102` set VALID by hand, and no IPv4 or DHCP. `netinfo_dhcp_wait/summary` sit in the
    IPv4 branch.
  - **AXI EmacLite has no multicast or promiscuous reception** (xemaclite.h feature list), so NDP and RAs never
    arrive. Only link-local works, and only with a static neighbor entry on the PC.
  - Real IPv6 would need AXI 1G/2.5G Ethernet (TEMAC license + DMA).
  - Not built or tested on the board.
- **`updatemem` journal:** `updatemem` writes `updatemem.jou/.log` into the current directory. The Makefile runs it in `build/sw`.
- **lwIP check:** `empyro config_bsp -al lwip220` fails without an Ethernet instance ("lwip220 requires at least
  one ethernet hardware instance"). That is expected, and it is why lwIP is added only when a MAC is present.
- **Known BSP warnings:** `-Woverflow` / "excess elements" warnings in the generated `xmicroblaze_riscv_g.c`
  come from AMD and appear in Vitis builds too.
- **Console capture:** only one process gets the UART's bytes. An open `minicom`/`make console` takes them all, so a
  second reader sees nothing, which looks like a dead UART. Check with `ls -l /proc/*/fd | grep ttyUSB1` first.
  Also, the FTDI chip keeps output from before the port was opened (e.g. the flashed program's banner at power-up).
- **Debugging on the board with xsdb:** this is how the two bugs above were found.
  - **Target:** the CPU target is called **"Hart #0"**, under "RISC-V at USER2" (BSCAN), so filter `*hart*`.
  - **Where is it?** `memmap -file app.elf`, then `stop`, `bt` and `con`.
  - **Variables:** `mrd -value <addr from nm>` reads them, and peripheral registers the same way.
  - **Always resume:** use `catch {stop}` and finish with `catch {con}`. A script error before `con` leaves the CPU
    halted (it happened once).
  - **No `rrd mstatus`:** CSRs aren't available under that name ("no register match").
  - **Halting changes things:** every `stop` pauses interrupt handling, so register snapshots can show a frame
    "pending" that the ISR would have taken a moment later. Confirm with behaviour (ping/latency), not just with snapshots.
- **GDB / VS Code debugging:**
  - **Ports:** hw_server opens GDB servers per architecture: 3000 ARM32, 3001 ARM64, 3002 MB32, 3003 MB64,
    **3004 RISC-V 32** (MicroBlaze V) and 3005 RISC-V 64. Use `riscv32-xilinx-elf-gdb` with
    `target extended-remote localhost:3004`.
  - **`make debug-load APP=x`:** `run.sh -p -s` configures the FPGA, then `dow`, and leaves the CPU halted at the entry
    (0x0 for demo, 0x80000000 for echo).
  - **`.vscode/launch.json` (cppdbg):** `useExtendedRemote`, `postRemoteConnectCommands: tbreak main` and
    `launchCompleteCommand: exec-continue` for Debug; `None` for Attach. These keys were checked against cpptools 1.35.6.
    `scripts/hw_server.sh` starts hw_server for Attach if no Vivado/xsdb started it.
  - **Verified on the board with command-line gdb:**
    - demo: tbreak main, next, a breakpoint in `eth_check`, bt.
    - echo in DDR: main, then `start_application` after DHCP. The network was fine afterwards.
  - **"Debug program of open file":** the task runs `make debug-load FILE=${relativeFile}`. The top Makefile takes APP
    from the third path component (`sw/apps/<name>/…`, any depth, so `modules/rgb/rgb.c` → demo). `debug-load` links
    `build/sw/debug-app` → `<APP>`, and launch.json loads `build/sw/debug-app/app.elf`. (`${fileDirnameBasename}`, used
    before, gave `rgb` for files in subfolders.) With a file outside `sw/apps/`, make stops with "no sources … available apps".
  - **F5 uses the selected configuration:** it runs the configuration selected in the Run and Debug dropdown, which
    is easy to forget when switching between programs ("Debug demo" starts although echo was wanted).
  - **The VS Code UI path works on the board:** F5 with Debug demo/echo and "Debug program of open file". Stopping a
    session and starting a new one works without problems.
  - **gdb charset warning:** `could not convert ... ANSI_X3.4-1968` appears only when LANG is unset. Harmless.
- **Instruction check:** after toolchain or flag changes, check that there are no `mul/div/rem/amo/c.*` instructions:
  `riscv32-xilinx-elf-objdump -d build/sw/<APP>/app.elf | awk '{print $3}' | grep -cE '^(mul|div|rem|amo|c\.)'` → 0.
  Also check that the entry point and `_boot` are at 0x0 (LMB apps) or 0x80000000 (DDR apps), and that
  `mbv_data_restore` is the first `.init_array` entry.

## Verified so far

- **Batch build:** `make hw`, including the refusal paths (unexported edits, GUI open, lock).
- **Fingerprint / IP cache:**
  - `REBUILD=1 make hw`: 15 min, fills the cache.
  - `make hw` without changes: 13 s, "nothing to do", BSP untouched.
  - `REBUILD=1 make hw` again: 10 min, using 14 cached IPs. Same result, WNS +1.236.
- **Ethernet + QSPI + timer:**
  - Hardware build: 10 min with the IP cache, WNS +1.312.
  - `eth_ref_clk` is exactly 25.000 MHz (40.000 ns) in timing.rpt.
  - The BSP auto-added lwip220 and built `liblwip220.a`; drivers emaclite, spi and tmrctr are present.
  - The demo with the PHY and flash checks builds (then about 42 KB of code and data, 35 % of the LMB including the
    `.noinit` copy) and runs on the board.
- **RGB LEDs (axi_gpio_2):**
  - Added by scripted Tcl against `build/hw/proj` + `mbv::export_bd` (`apply_board_connection -board_interface rgb_led`).
  - `make hw`: 10 min with the IP cache, WNS +1.316, WHS +0.021.
  - The BSP has `XPAR_XGPIO_2_BASEADDR 0x40020000` and `GPIO_WIDTH 12`.
  - `system_wrapper_io_placed.rpt` puts `rgb_led_tri_o[0..11]` on E1 F6 G6 / G4 J4 G3 / H4 J2 J3 / K2 H6 K1, the board file's order.
  - demo, echo and boot build without warnings and without M/A/C instructions. The demo uses about 47 KB of the LMB (`_heap_start` 0xbb50).
- **Echo server build:**
  - `make APP=echo` builds without warnings: entry 0x80000000, lwIP linked, no M/A/C instructions.
  - `make APP=echo program` explains that DDR programs need `make run`.
  - `make run APP=echo` without a board fails cleanly. On the board, see below.
- **GUI:** `make gui` (over a borrowed ssh display). "MBV: Export BD" with no changes reports up to date,
  and the exported Tcl matches the original exactly. "MBV: Build HW + BSP" on a fresh project took 15 min,
  with WNS +1.236, and produced the BSP. After that, `make` builds the app.

## Verified on the board (Arty A7-100T)

- **Console and programs:**
  - `console.py` on the Digilent `-if01-port0` port (`/dev/ttyUSB1`) works.
  - The demo's PHY/link and flash JEDEC lines on the console are correct.
  - VS Code debugging (Debug/Attach configurations, stop and restart a session) works.
  - The echo startup report (`netinfo.c`) and the demo running from flash, including after RESET, work.
  - `make program` works; xsdb target "Hart #0" matches `*hart*`.
- **`make run APP=echo`:** `run.sh -p` configures the FPGA via xsdb `fpga -file`, finds "Hart #0", then `dow` and `con`.
- **`make flash`:** the board's flash is the **Spansion S25FL128S** (Mfg ID 0x01, type 0x20, capacity 0x18), so the default
  `FLASH_PART` is correct. Erase, program and verify of the ~2.2 MB `.mcs` take several minutes. `flash.sh` now streams
  Vivado's progress lines (it used to look hung).
- **Bootloader:**
  - `make flash APP=echo` writes `boot/download.bit` at 0 and `echo/app.img` (78,862 bytes) at 0x400000. After the reboot
    from flash the echo server answers: ping 0.67 ms, TCP echo OK.
  - After an xsdb CPU reset (PC 0x0 = bootloader) the board answers again within 12 s (load + DHCP): ping 0.53 ms, echo OK.
  - The physical RESET button and power-cycling work with the bootloader and echo flashed.
  - `make run` stays independent of the bootloader: plain `system.bit` over JTAG plus `dow` into DDR, quick and volatile.
    After RESET nothing runs; PROG or power-up brings back the flashed program.
- **Echo server:**
  - The XTimer tick works (`dhcp_timoutcntr` drops about 20/s).
  - DHCP on a normal home/office network works; the echo answers from another PC on the same network.
  - With `emaclite_drain_rx()`: ping 0.5 ms, TCP echo OK, 26 KB byte-identical.

- **RGB LEDs (demo):** (with the earlier free-running rainbow, before the timer sequence) `rgb_selftest()` passes (readback, also checked over JTAG). Each LED shows red, green and blue
  in the right order, then white and the ramp. The rainbow runs without visible flicker.

## Not yet verified on hardware

- **axi_timer_1 RGB sequence:** hardware built (10 min with the IP cache, WNS +1.259, WHS +0.020; BSP has
  `XPAR_XTMRCTR_1_BASEADDR 0x41c10000`, `XPAR_XTMRCTR_1_INTERRUPTS 0x2005`, `XPAR_XINTC_0_NUM_INTR_INPUTS 0x6`).
  demo/boot/echo build without warnings or M/A/C instructions; demo uses 49 KB of the LMB. Not run on the board yet
  (none was connected): check the 1 s rotation / 1 s off by eye, also after RESET.
- **QSPI beyond RDID/READ:** `C_SPI_MEMORY=2` comes from the board preset. Program/erase from software isn't tested
  (only `make flash` through Vivado, and the bootloader's reads).
- **IPv6:** not built or tested (see the gotcha).
- **Fast interrupts:** with the INTC in fast mode (`C_HAS_FAST=1`), any app that registers *fast* handlers is
  untested. lwIP/xiltimer use normal mode (IMR=0 seen on the board).

## Conventions

- **Docs:** keep this file and README.md current with every change. Update the facts, commands, address map,
  gotchas and the "not yet verified" list as part of the work, not afterwards.
- **Act, don't ask:** pick the recommended approach and do the work, rather than asking multiple-choice
  questions.
- **License:** MIT (`LICENSE`). Files copied from AMD's embeddedsw keep
  their own MIT headers. Don't strip them, and note new copies in the README "License" section.
- **File headers:** every source file we write starts with `Author: w1gx` and `Date: <creation date>` in its comment
  style, after the `#!` line if there is one. New files get it too. There is no header on AMD's template files,
  the Digilent-based `hw/arty_a7_100.xdc`, the generated `hw/system_bd.tcl` (Export BD rewrites it), the
  `sw/drivers/xparameters.h` symlink (it points into the generated BSP), or JSON/Markdown.
- **Commits:** commit only when asked. Commits end with the `Co-Authored-By` trailer. Branch: `main`; push only when asked.
- **Never open `build/hw/proj/mb_v.xpr` directly:** use `make gui`. Opening it directly gives no MBV buttons, no
  export to `hw/system_bd.tcl`, and Generate Bitstream doesn't produce the `.mmi`/`.xsa`/BSP. README
  has an IMPORTANT callout about this. Point users to it. README "The two toolbar buttons" documents
  each button step by step, including its console messages. Keep it in sync with `hw/project.tcl` / `hw/gui/*.tcl`.
- **Hardware changes:** go through the GUI (`make gui` + MBV buttons) or scripted Tcl against
  `build/hw/proj` followed by `mbv::export_bd`. Always end with `hw/system_bd.tcl` updated.
- **Board interfaces available:** `led_4bits`, `rgb_led`, `push_buttons_4bits`, `dip_switches_4bits`,
  `eth_mii`, `qspi_flash`, `spi`, `i2c_pullups`, `shield_dp0_dp19`, `shield_dp26_dp41`, `usb_uart`, `ddr3_sdram`.
