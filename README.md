# MicroBlaze V on Arty A7-100, without Vitis

Hardware, drivers and software are built from plain scripts, using only
command-line tools that ship with Vivado:

- **Hardware:** Vivado in batch mode
- **BSP:** `sdtgen` and `empyro` (AMD's own BSP generator)
- **Application:** `riscv32-xilinx-elf-gcc` and `make`
- **Program into bitstream:** `updatemem`
- **Programming the board:** Vivado hardware manager and `xsdb`

The Vitis IDE is not used.

```
make hw          # after changing hw/ (~15 min; about 1 min if nothing changed)
make             # compile, link, merge into the bitstream (seconds)
make program     # load over JTAG
make console     # 115200 8N1 on the USB-UART, Ctrl-] quits
make flash       # write to the SPI flash, boots at power-up (3-5 min, shows progress)
make bsp         # regenerate only the BSP, e.g. after editing sw/bsp.conf
make gui         # edit the block design in Vivado
make debug-load  # load a program halted for the debugger (VS Code: F5, see "Debugging")

make run APP=echo     # lwIP echo server, loaded into DDR through the debugger (see "Programs")
make flash APP=echo   # echo server + bootloader into flash, starts at power-up
```
`APP=<name>` picks the program in `sw/apps/` for every command (default `demo`).

## VS Code

Open the `mb-test` folder itself (File → Open Folder), not a subfolder. The settings
in `.vscode/` only apply when this folder is the workspace root. Install the
recommended **C/C++** extension (`ms-vscode.cpptools`) when VS Code asks.

### IntelliSense

`make` writes `build/sw/compile_commands.json` with the exact compile command of every
file in `sw/apps/` (every program). `.vscode/c_cpp_properties.json` points the C/C++ extension at it.
IntelliSense then uses the same compiler, `-march`/`-mabi`, defines and include paths as
the real build, so it finds:

- your own headers in `sw/apps/<program>/`
- the BSP: `xparameters.h`, every driver header (`xgpio.h`, `xuartlite_l.h`, ...),
  `xil_printf.h`, `sleep.h`, ...
- the RISC-V C library (`stdio.h`, `stdint.h`, ...)

Nothing needs updating by hand. After adding hardware, `make hw` or the GUI build plus
`make` brings in the new driver headers. New `.c` files in `sw/apps/` are picked up by
the next `make`.

- **On a fresh clone:** `build/` doesn't exist yet, so build once (`make hw`, then
  `make`) before IntelliSense resolves the BSP headers. Until then a fallback
  configuration covers `sw/apps` and the compiler's own headers.
- **Browsing the BSP:** `sw/drivers/xparameters.h` is a link to the generated
  `xparameters.h`, for quick access. Ctrl+click on any driver function or `XPAR_*`
  name jumps into the BSP sources in `build/bsp/domain/`.
- **If headers are still red after a build:**
  1. Run "C/C++: Select a Configuration" and pick **MicroBlaze V**.
  2. If that doesn't help, run "C/C++: Reset IntelliSense Database".
  3. Turn down any offer from the Makefile Tools extension to configure the project.
     It is disabled for this workspace on purpose.

### Tasks

**Ctrl+Shift+B** runs `make` (the default build task) and asks which program in `sw/apps/`
to build (*demo* or *echo*). The program, flash and run tasks ask the same. Compiler errors and warnings
appear in the Problems panel and are clickable. Everything else is under
**Terminal → Run Task**:

| Task | Runs | What it does |
|---|---|---|
| build | `make APP=…` | Compile and link. Block-RAM programs also get `download.bit`, DDR programs `app.img` |
| program (JTAG) | `make program APP=…` | Load `download.bit` into the FPGA (block-RAM programs) |
| console | `scripts/console.py` | Serial terminal in its own panel (type into it; Ctrl+] quits) |
| program + console | both | Program, then open the console |
| flash (SPI) | `make flash APP=…` | Write to the configuration flash. DDR programs go in together with the bootloader |
| run (xsdb, e.g. echo) | `make run APP=…` | Configure the FPGA with the plain hardware, load `app.elf` through the debugger. Needed for DDR programs such as *echo* |
| debug: load … | `make debug-load APP=…` | Used by the debug configurations: load the program halted at its entry point |
| debug: hw_server | `scripts/hw_server.sh` | Used by the *Attach* configurations: start AMD's `hw_server` if it isn't running |
| open block design in Vivado | `make gui` | Vivado GUI with the MBV toolbar buttons |
| build hardware + BSP | `make hw` | Batch hardware build (~15 min) |
| regenerate BSP | `make bsp` | After editing `sw/bsp.conf` |
| clean | `make clean` | Remove `build/sw` |

### Vivado GUI from VS Code (Remote-SSH)

VS Code's Remote-SSH terminals usually have no X display, so Vivado can't open a
window. If `DISPLAY` is missing or doesn't work, `make gui` borrows a working display from
one of your other sessions on this machine, for example an `ssh -X` terminal or
MobaXterm, and says which one it uses. The window then appears where that session's X server
runs, and **Vivado closes when that session ends**. With no usable display at all,
`make gui` stops with a message. `make gui` waits until Vivado has the project open
(about 30 s) and reports a failed start, with the crash report if there is one. Over ssh
forwarding a start has failed once with an X11 error. Running it again worked.

To give VS Code its own display, enable X11 forwarding for the Remote-SSH connection:
- **SSH config:** add `ForwardX11 yes` (or `ForwardX11Trusted yes`) to the host's entry in the
  ssh config on the machine running VS Code.
- **Local X server:** run one there, and make sure `DISPLAY` is set in the environment VS Code
  starts from (Remote-SSH setting `remote.SSH.enableX11Forwarding`).
- **Reconnect:** open a new connection. VS Code terminals then show `DISPLAY=localhost:1x.0`.

### Debugging (F5)

The **Run and Debug** view (Ctrl+Shift+D) has five configurations. They use the C/C++ extension with
`riscv32-xilinx-elf-gdb`, which connects to AMD's `hw_server` (GDB server for RISC-V on port
**3004**):

| Configuration | What happens |
|---|---|
| **Debug program of open file** | Like *Debug demo/echo*, for the program whose source file is open in the active editor (`sw/apps/echo/…` → echo). |
| **Debug demo** / **Debug echo** | Builds the program, configures the FPGA, loads the program and stops at `main()`. Then step, set breakpoints, watch variables as usual. |
| **Attach demo** / **Attach echo** | Connects to whatever is running right now (e.g. started from flash or with `make run`) and stops where it is. Nothing is reloaded. Pick the configuration that matches the running program. |

- **Choosing the configuration:** **F5 always starts the configuration selected at the top of the Run and Debug view**
  (it remembers the last one). Switch it in that dropdown, or use *Debug: Select and Start Debugging*.
- **Breakpoints:** they work in both the local memory (demo) and DDR (echo). Interrupts and the
  network keep running while the program runs under the debugger.
- **Console:** keep `make console` open alongside, because the UART output is independent of the debugger.
- **After a session:** stopping a session and starting a new one (F5 again) works. To let the board run
  on its own again, start a program with `make run`, `make program` or the PROG button.
- **Without VS Code:** `make debug-load APP=<name>` loads the program halted at its entry point, then
  attach any GDB with `target extended-remote localhost:3004`.

#### Example: stepping through the echo server

1. **Start the console** in a terminal: `make console`. The program's output, including the board's IP
   address, appears there.
2. **Start the debugger:** open `sw/apps/echo/echo.c`, select **Debug program of open file** (or
   **Debug echo**) in the Run and Debug view, and press **F5**. VS Code builds the echo server,
   configures the FPGA, loads the program into DDR and stops at `main()` in `sw/apps/echo/main.c`.
3. **Set breakpoints** in `echo.c` by clicking left of the line numbers:
   - in `accept_callback()`, hit once per new TCP connection
   - in `recv_callback()`, hit for every packet the board receives on port 7
4. **Let it run:** press **F5** (Continue). The console shows the network report and
   `Echo server ready on TCP port 7. From your PC:  nc <ip> 7`.
5. **Connect from your PC:** `nc <ip> 7`, then type a line and press Enter. VS Code stops in
   `accept_callback()` when the connection opens, and in `recv_callback()` when the line arrives.
6. **Look around:**
   - The *Variables* panel shows `p` (the received lwIP buffer) and `tpcb` (the connection).
   - In *Watch*, add `(char *)p->payload` to see the received text, and `p->len` for its length.
   - *Call Stack* shows how the packet got there: from the main loop in `main.c` through lwIP's input
     processing (functions like `xemacif_input` and `tcp_input`) to `recv_callback`.
7. **Step:** F10 steps over lines up to `tcp_write()`, which sends the data back. F5 continues, and the
   text appears in `nc`.

- **Paused means paused:** while the CPU is stopped at a breakpoint, the whole board is paused, including
  timers and lwIP. The PC simply waits: TCP retransmits and nothing is lost. Long pauses can still make
  your PC give up on the connection, or let a DHCP lease run out.
- **The same works for the demo:** open `sw/apps/demo/main.c`, set a breakpoint, e.g. in `eth_check()`
  or `flash_check()`, and press F5 with *Debug program of open file*.

### Editor settings

`.vscode/settings.json` leaves the throw-away Vivado project (`build/hw/proj`) out of
search and the file watcher, so VS Code stays fast. The generated BSP
(`build/bsp/domain`) stays searchable. `.xdc` files open as Tcl.

## How drivers get there

`make hw` ends by running `scripts/build_bsp.sh`, which does the same steps as
Vitis' platform build:

1. **Device tree:** `sdtgen` turns `build/hw/out/system.xsa` into a system device tree (`build/bsp/sdt`).
2. **BSP:** `empyro create_bsp` picks a driver for every IP in the design (GPIO, UART Lite,
   INTC, BRAM, ...) from the embeddedsw repository in the Vivado install. It generates
   `xparameters.h` and each driver's config table, and adds AMD's standalone runtime:
   startup code, `xil_printf`, caches, exceptions and `sleep`/`usleep` (xiltimer).
3. **Libraries:** libraries listed in `sw/bsp.conf` are added with `empyro config_bsp`.
   **lwip220 is added automatically when the design has an Ethernet MAC** (AXI Ethernet Lite
   or AXI Ethernet). Library options go in `sw/bsp.conf` as well.
4. **Build:** `empyro build_bsp` compiles everything into `build/bsp/domain/lib/*.a`.
   Headers end up in `build/bsp/domain/include`.

The application Makefile links every library the BSP built, so a new
peripheral or library needs no Makefile change. Add the IP, `make hw`, and
`#include "xgpio.h"` (or whichever driver) in your code.

## Layout

| Path | What |
|---|---|
| `hw/system_bd.tcl` | Block design: MicroBlaze V, 128 KB LMB, 16 KB I/D cache, MIG DDR3, UART Lite, AXI GPIO 0 (LEDs, `0x40000000`), AXI GPIO 1 (ch 1 push buttons, ch 2 DIP switches, `0x40010000`), AXI Ethernet Lite (`0x40E00000`), AXI Quad SPI on the configuration flash (`0x44A00000`), AXI Timer (`0x41C00000`), AXI INTC (interrupts: 0 UART, 1 buttons/switches, 2 Ethernet, 3 QSPI, 4 timer), MDM. Exported with `write_bd_tcl`. |
| `hw/arty_a7_100.xdc` | The two clock pins (`sys_clk_i` in, `eth_ref_clk` out), configuration settings (quad-SPI boot) |
| `hw/project.tcl` | Shared Vivado procedures: create the project, export the block design, build, BSP |
| `hw/build_hw.tcl`, `hw/build_hw.sh` | `make hw`: recreate the project in `build/hw/proj`, synthesis, implementation, outputs to `build/hw/out`, then the BSP |
| `hw/gui.tcl`, `hw/gui/`, `scripts/gui.sh` | `make gui`: Vivado GUI with the MBV toolbar commands (icons in `hw/gui/icons/`) |
| `hw/gen_memmap.tcl` | `memory.ld` (LMB/DDR regions) and `cpu.mk` (`-march`/`-mabi`) from the block design |
| `scripts/build_bsp.sh`, `sw/bsp.conf` | BSP generation (see above) and its configuration |
| `sw/` | `link.ld`, `Makefile`, `bsp.conf`, `apps/<program>/` (one directory per program: `demo`, `echo`, `boot`), `common/` (built into every program: `data_restore.c`, `mbv_image.h`), `drivers/xparameters.h` (link to the generated file) |
| `scripts/` | `program.sh` (JTAG), `flash.sh` (SPI flash), `run.sh` (xsdb load, `-s` = halted), `console.py`, `mkimage.py` (flash image for the bootloader), `hw_server.sh`, `build_bsp.sh`, `gui.sh`, shared `env.sh` |
| `.vscode/` | IntelliSense configuration, tasks, debug configurations (`launch.json`), editor settings |
| `build/` | Everything generated, safe to delete |

## Changing the hardware

> [!IMPORTANT]
> **Don't open `build/hw/proj/mb_v.xpr` in Vivado yourself. Always use `make gui`.**
> The project in `build/` is generated from `hw/system_bd.tcl` and gets recreated by
> `make hw`. If you open it directly:
> - **No MBV buttons:** the toolbar commands are only added by `make gui`.
> - **Edits stay in the project:** nothing writes them to `hw/system_bd.tcl`, so they never
>   reach git.
> - **The software sees nothing:** Vivado's own *Generate Bitstream* does not write the
>   `.mmi`, `.xsa`, memory map or BSP that `make` needs.
> - **`make hw` refuses to run** while the edits are unexported, and `FORCE=1` throws them away.
>
> Use `make gui`, then **MBV: Build HW + BSP**. If you already edited the project
> directly, open it with `make gui` and click **MBV: Export BD** to save your work.

`make gui` opens the Vivado project (`build/hw/proj`) in the GUI. It creates the
project from `hw/system_bd.tcl` first if there isn't one. Edit the block design
as usual (add IP, change settings, run connection automation), then use one of
the two **MBV** buttons that `make gui` adds to Vivado's toolbar.

### The two toolbar buttons

| Button | Name | Use it to | Takes |
|---|---|---|---|
| <img src="hw/gui/icons/export_bd.png" width="24"> | **MBV: Export BD** | Save your block-design changes into the repository | seconds |
| <img src="hw/gui/icons/build.png" width="24"> | **MBV: Build HW + BSP** | Turn the block design into everything the software build needs | ~15 min (~1 min if nothing changed) |

The buttons sit on the main toolbar, with a green arrow and an orange hammer. Hover over one to
see its name, and both are also under **Tools → Custom Commands**. Their messages appear in
Vivado's **Tcl Console**, each starting with `mbv:`.

**MBV: Export BD** (green arrow):
1. Validates the block design, the same check as Vivado's *Validate Design*, and saves it.
2. Writes it with `write_bd_tcl` and compares that with `hw/system_bd.tcl`. Comments are ignored.
3. If they differ, replaces `hw/system_bd.tcl` and prints
   `mbv: exported block design to hw/system_bd.tcl`. Otherwise it prints
   `mbv: hw/system_bd.tcl is up to date` and touches nothing.

Use it whenever you want to keep a change, even before building. Then review
and commit `hw/system_bd.tcl` (`git diff hw/system_bd.tcl`). It doesn't build anything.

**MBV: Build HW + BSP** (orange hammer):
1. Does everything *Export BD* does, so a build always matches `hw/system_bd.tcl`.
2. Runs synthesis, implementation and bitstream generation in the open project. If the
   design hasn't changed since the last build, it skips straight to step 3. If
   `build/hw/out` already matches the design's fingerprint, it skips steps 2 and 3
   entirely (see below).
3. Writes `build/hw/out`: `system.bit`, `system.mmi`, `system.xsa`, `memory.ld`, `cpu.mk`
   and the timing and utilization reports. The console shows `BUILD_HW_RESULT wns=… whs=…`.
   Negative numbers mean timing is not met, and a warning is printed.
4. Generates the BSP for the new hardware (`scripts/build_bsp.sh`), so drivers for
   new IP show up in `build/bsp/domain`. The console lists the drivers it found, or prints
   `mbv: BSP is up to date` if the hardware file didn't change.
5. Finishes with `mbv: hardware and BSP done - run make for the software`.

Vivado is busy while it runs: the window updates and shows run progress, but wait for
the final message before editing or clicking again. It does **not** compile your
program or touch the board. Run `make` and `make program` afterwards (or the VS Code tasks).

### Typical workflow

1. `make gui` (or the VS Code task *open block design in Vivado*).
2. Change the block design in Vivado.
3. Click **MBV: Build HW + BSP** and wait for `mbv: hardware and BSP done`.
4. `make`, then `make program && make console`. Use the new peripheral's driver from the BSP
   (`#include "xgpio.h"` etc.).
5. `git add hw/system_bd.tcl` along with your code and commit.

If you only want to save work in progress, click **MBV: Export BD** instead of building.

**Rebuilds are skipped when nothing changed.** Every hardware build stores a fingerprint of
its sources in `build/hw/out/source.fingerprint`: the block design and constraints (comments
ignored), part, board and Vivado version. If `make hw` or **MBV: Build HW + BSP** finds the
same fingerprint, it reports `build/hw/out was already built from this design` and stops.
That holds even when the Vivado project was just recreated. `REBUILD=1 make hw` forces a full
build anyway. The BSP is only regenerated when the hardware file or `sw/bsp.conf` changed.

**Synthesized IP is cached** in `build/hw/ipcache`, outside the project folder. When the
project is recreated (`make hw`, `make gui FRESH=1`), IP blocks whose settings didn't change
(CPU, interconnect, GPIO, UART, ...) come from the cache instead of being synthesized again.
A full rebuild then takes about 10 minutes instead of 15. The DDR3 controller (MIG) is the
one block Vivado doesn't cache, so it is always synthesized again.

`make` never starts the 15-minute hardware build on its own. If something in `hw/` is
newer than the bitstream, it builds the software anyway and prints a warning to run `make hw`.
Only one hardware build can run at a time. A second `make hw` stops immediately.

`hw/system_bd.tcl` is the version that matters: it goes into git, and `make hw` rebuilds
the project from it in batch mode. `make hw` stops if the project has block-design
changes that were never exported, so GUI work can't be lost by accident. `FORCE=1 make hw`
discards them. If `hw/system_bd.tcl` changed underneath the project (for example after
a `git pull`), `make gui FRESH=1` recreates the project from it.

The board files come from the Vivado board store (`BOARD_REPO` in `scripts/env.sh`),
so board interfaces such as `led_4bits`, `push_buttons_4bits`, `eth_mii` and `qspi_flash`
are available. New peripherals get their drivers in the BSP automatically.

## Clocking and porting to another board

The only clock coming into the design is **`sys_clk_i`**: the Arty's 100 MHz oscillator on pin E3.
The block design has an input port of that name, and **its pin is defined only in
`hw/arty_a7_100.xdc`**. Keep the port name and that constraint, or the build fails on an unplaced clock pin.
The clock period comes from the DDR3 controller (MIG), which generates its own `create_clock` for
`sys_clk_i`. That's why the `create_clock` line in our xdc is commented out.

From that clock the MIG makes everything else:

| Clock | Frequency | Used by |
|---|---|---|
| `sys_clk_i` (pin E3) | 100 MHz | MIG input only |
| `ui_clk` | 81.25 MHz | CPU, local memory, all AXI peripherals |
| `ui_addn_clk_0` | 200 MHz | the MIG's own reference clock (`clk_ref_i`), and the Ethernet clock wizard |
| `eth_ref_clk` (pin G18) | 25 MHz | the Ethernet PHY's reference clock: 200 MHz / 8, output by the FPGA |

The Ethernet PHY on the Arty has no crystal of its own. The FPGA generates its 25 MHz
clock and drives it out on pin G18. That's the **second clock pin in `hw/arty_a7_100.xdc`**
(`eth_ref_clk`), again not covered by the board files. Ethernet needs this clock within
±50 ppm, so it comes from the MIG's exact 200 MHz with a 1:8 ratio. Check the real
frequencies in the timing report (`build/hw/out/timing.rpt`, *Clock Summary*), because the
block design shows rounded values.

The UART's clock frequency is entered by hand in the block design
(`C_S_AXI_ACLK_FREQ_HZ_d = 81.25`). Its baud rate is computed from that, so it must be
updated whenever the system clock changes.

**On another board**, check at least:
1. **Board part:** `hw/project.tcl` (`part`, `board_part`) and the board files.
2. **Clock pin:** the `sys_clk_i` pin and I/O standard in the xdc.
3. **DDR controller:** the MIG's DDR preset, and that its input clock matches the board's oscillator.
4. **UART:** its clock setting.
5. **Board-interface names:** UART, LEDs, buttons, switches, Ethernet (`eth_mii`, `eth_mdio_mdc`),
   QSPI (`qspi_flash`), plus the Ethernet PHY clock pin, if the new PHY needs one.
6. **Flash:** `FLASH_PART` for flashing.

`CLAUDE.md` (section Clocking) has the details, including what changes for a board without DDR.

## Programs

Every directory in `sw/apps/` is a program, chosen with `APP=` (default `demo`). Output goes to
`build/sw/<APP>/`. An optional `app.mk` in the directory sets per-program defaults
(`RUN_FROM`, `APP_CFLAGS`). To add a program, create `sw/apps/<name>/` with its `.c` files and
build it with `make APP=<name>`.

| Program | Runs from | Load with | What it does |
|---|---|---|---|
| `demo` | local memory | `make program` (or `make flash`) | Hardware summary, DDR test, Ethernet PHY and flash checks, LEDs/buttons/switches, UART echo |
| `echo` | DDR | `make run APP=echo` (debugger) or `make flash APP=echo` (bootloader) | lwIP TCP echo server on port 7 |
| `boot` | local memory | used by `make flash` for DDR programs; `make program APP=boot` tests it without reflashing | Bootloader: copies a DDR program from flash to DDR at every start |

### Where a program runs: block RAM or DDR

Every program runs either from the **local memory** (128 KB of block RAM at `0x00000000`, also
called LMB) or from **DDR3** (256 MB at `0x80000000`). Code, data, heap and stack all go into the
chosen memory. It's selected with the variable **`RUN_FROM`**, in this order:

1. **Command line:** `make APP=demo RUN_FROM=DDR` overrides everything for that build.
2. **The program's `sw/apps/<name>/app.mk`:** the permanent setting for one program. `sw/apps/echo/app.mk`
   contains
   ```make
   RUN_FROM := DDR
   ```
3. **Default:** `LMB` (block RAM), when neither is set. `demo` and `boot` have no `app.mk` setting.

`RUN_FROM` only takes `LMB` or `DDR` (they are the region names from `build/hw/out/memory.ld`).
The linker script `sw/link.ld` places everything in that region (`REGION_ALIAS("CODE", …)`).

| | `RUN_FROM=LMB` (default) | `RUN_FROM=DDR` |
|---|---|---|
| Space | 128 KB for code + data + heap, minus an 8 KB stack | 256 MB |
| Speed | single-cycle memory, no cache needed | through the 16 KB caches |
| Build output | `app.elf` + `download.bit` (the program is part of the bitstream) | `app.elf` + `app.img` (flash image) |
| Try it | `make program APP=<name>` | `make run APP=<name>` (debugger, until RESET) |
| Keep it | `make flash APP=<name>`: starts at power-up | `make flash APP=<name>`: with the bootloader, see below |
| After RESET | restarts (`sw/common/data_restore.c`) | restarts via the bootloader if flashed; after `make run`, nothing runs |
| Good for | small programs, things that must start instantly | big programs, lwIP |

**How do I know it fits?** Every link prints the memory use, e.g.
```
Memory region         Used Size  Region Size  %age Used
             LMB:       46244 B       128 KB     35.28%
```
If a program grows too big for the local memory, the link fails with
`program does not fit in the CODE region`. You can then either switch the program to `RUN_FROM := DDR`, or
keep the code in block RAM and move only big buffers into DDR:
```c
static uint8_t frame[1 << 20] __attribute__((section(".ddr")));   /* 1 MB in DDR, not zeroed */
```
The demo does that for its DDR test. Such buffers are not cleared and not loaded at startup.

**Making a new program run from DDR:** create `sw/apps/<name>/app.mk` with `RUN_FROM := DDR`. From
then on `make`, `make run` and `make flash` (with bootloader) do the right thing for it, and the VS Code
tasks and debug configurations follow automatically.

### lwIP echo server (`APP=echo`)

AMD's *lwIP Echo Server* template, the one Vitis offers, built with our flow, plus a startup
report of the network configuration (`netinfo.c`) and a fix for lost Ethernet receive interrupts
(`emaclite_rx.c`). See `sw/apps/echo/README.md`. Tested on the board: 0.5 ms ping, TCP echo of
26 KB byte-identical.

1. Plug the Arty into your network with an Ethernet cable.
2. `make APP=echo && make run APP=echo`. This configures the FPGA with the plain
   hardware and loads the program into DDR through the debugger.
3. `make console` shows the startup report. The board asks for an address by DHCP and, without a DHCP
   server, falls back to **192.168.1.10** (netmask 255.255.255.0, gateway 192.168.1.1)
   after about 12 seconds. The values below are examples:
   ```
   Ethernet interface
     controller  : AXI Ethernet Lite at 0x40e00000, 10/100 Mbit/s MII
     MAC address : 00:0a:35:00:01:02

   Requesting an IP address by DHCP (falls back to 192.168.1.10 after ~12 s) ...

   Network configuration
     PHY         : TI DP83848, MDIO address 1 (ID 2000:5c90)
     link        : up, 100 Mbit/s, full duplex
     address from: DHCP, server 192.168.0.1, lease 86400 s
     IP address  : 192.168.0.57
     netmask     : 255.255.255.0
     gateway     : 192.168.0.1

   Echo server ready on TCP port 7. From your PC:  nc 192.168.0.57 7
   ```
4. From your PC: `nc <board-ip> 7` (or `telnet <board-ip> 7`). Everything you type comes
   back.

- **MAC address:** `00:0a:35:00:01:02` (AMD's example address, set in `main.c`). Change it if two
  boards share a network.
- **BSP settings:** the echo server's lwIP and timer settings are in `sw/bsp.conf`: DHCP, 2048 packet buffers,
  and the AXI Timer as tick. Change them there and run `make bsp`.
- **`make run` vs. `make flash`:**
  - `make run APP=echo` loads the program into DDR through the debugger, which is good for trying it
    out. It doesn't survive RESET: the local memory is empty, and that's where the CPU starts.
  - `make flash APP=echo` stores it permanently together with the bootloader (see below). It then
    starts at power-up, after PROG and after RESET.
  - A typical cycle is to develop with `make run` (seconds, flash untouched), then `make flash` once it's done.
    After a `make run` session, PROG brings back the flashed version.

#### IPv6

lwIP's options, IPv6 included, are BSP settings, not `#define`s in the code. They are set in
`sw/bsp.conf`, and `make bsp` writes them into `build/bsp/domain/include/lwipopts.h`.
`lwip220_ipv6_enable:true` gives `LWIP_IPV6 1`, and the next `make` rebuilds the program against it.
The parameter names are in `build/bsp/domain/bsp.yaml`.

Mind the limits before switching it on:
- **IPv6-only echo server:** with IPv6 the template's `main.c` takes an IPv6-only path. There's no IPv4
  address and no DHCP, only a link-local address derived from the MAC (`fe80::20a:35ff:fe00:102`).
  The network report (`netinfo.c`) covers IPv4 only.
- **No multicast with AXI Ethernet Lite:** AMD's driver header says so. IPv6 neighbor discovery and
  router advertisements are multicast, so:
  - the board never gets a global address
  - your PC can't find it unless you add the neighbor entry by hand, e.g.
    `sudo ip -6 neigh add fe80::20a:35ff:fe00:102 lladdr 00:0a:35:00:01:02 dev <iface>`, then
    `nc -6 fe80::20a:35ff:fe00:102%<iface> 7`
- **Full IPv6** needs a MAC with multicast filtering, such as AMD's AXI 1G/2.5G Ethernet Subsystem.
  That needs a paid TEMAC license and an AXI DMA.

### Bootloader (`APP=boot`) for DDR programs

Programs too big for the local memory (such as `echo`) live in DDR, which is empty after power-up.
`make flash APP=<name>` therefore writes two things to the 16 MB flash:

| Flash address | Contents |
|---|---|
| `0x000000` | Bitstream with the bootloader (`sw/apps/boot`, ~18 KB) in the local memory |
| `0x400000` | The program image `build/sw/<name>/app.img`, made by `scripts/mkimage.py` from `app.elf` |

At every start (power-up, PROG, RESET) the bootloader:
1. reads the image header and checks it (magic, version, CRC)
2. copies the program into DDR and checks the CRC of what landed in DDR
3. writes the caches back and jumps to the program

The console shows each step:
```
MicroBlaze V bootloader: image at flash 0x00400000
boot: loading 'echo', 78862 bytes in 1 segment(s) ...
boot:   0x80000000  78862 bytes
boot: CRC ok, starting 'echo' at 0x80000000
```
followed by the program's own output. With no or a broken image it prints why and stops. Only
the program's code and initialised data go into the image (here about 77 KB). Its buffers and
other zeroed memory are cleared by the program itself. The image format is in
`sw/common/mbv_image.h`, and the 4 MB offset is set there in one place.

## Software notes

- **Ethernet and lwIP:** the BSP gets lwIP (`lwip220`) automatically because the design has an
  Ethernet MAC. lwIP is only linked into programs that use it. Its default buffers don't fit
  into the 128 KB local memory, so give lwIP programs `RUN_FROM := DDR` in their `app.mk` (as
  `echo` does; see "Where a program runs"), or make the buffers smaller in `sw/bsp.conf`
  (e.g. `lwip220 lwip220_mem_size:32768`). The AXI Timer provides lwIP's periodic tick.
- **RESET button:** restarts the program. Programs in the local memory get their initialised
  variables from the bitstream only once, so `sw/common/data_restore.c` (built into every program)
  saves them on the first start and restores them after each reset. Without it, `printf` printed
  nothing after a reset. The PROG button reloads the whole bitstream from flash instead.
- **QSPI flash:** `make flash` stores the bitstream at the start of the 16 MB flash. For DDR programs
  the program image sits at 4 MB (`0x00400000`). Keep your own data well above the image (e.g. from
  8 MB) so neither of them gets overwritten.
- **Startup checks:** the demo prints the Ethernet PHY's ID and link state (read over MDIO) and the
  flash's JEDEC ID. The ID line also names the `FLASH_PART` value `make flash` needs for this board.
- **Memory layout:** each program runs entirely from block RAM or entirely from DDR, chosen with
  `RUN_FROM`. See "Where a program runs: block RAM or DDR" under Programs. The stack is 8 KB
  (`_STACK_SIZE` in `sw/link.ld`), and the heap gets the rest of the chosen memory.
- **Names:** use AMD's names from `xparameters.h`, for example
  `XPAR_XGPIO_0_BASEADDR` and `XPAR_XUARTLITE_0_BASEADDR`. Drivers are initialised by base
  address: `XGpio_Initialize(&gpio, XPAR_XGPIO_0_BASEADDR)`.
- **printf:** `printf` maps to newlib's integer-only `iprintf`. Use `make PRINTF_FLOAT=1`
  to get floating point, which costs about 45 KB. `xil_printf` is smaller still.
- **Interrupts and exceptions:** these use AMD's API (`Xil_ExceptionRegisterHandler`,
  `XIntc_*`, or the `XSetupInterruptSystem` helper in `xinterrupt_wrap.h`). The AXI INTC
  is set to fast-interrupt mode (`C_HAS_FAST=1`).
- **Settings:** tool paths and the board-file location are in `scripts/env.sh`.
  Every value there can be overridden from the environment. `FLASH_PART`
  selects the flash chip for older board revisions (see `scripts/flash.sh`).

## License

MIT, see [`LICENSE`](LICENSE).

The echo server template files `sw/apps/echo/main.c`, `echo.c`, `platform.c` and `platform.h`
come from AMD's embeddedsw repository and keep their own MIT copyright headers (Xilinx/AMD).
The BSP, drivers and lwIP are generated into `build/` from the Vivado installation at build
time, are not part of this repository, and remain under their respective licenses.
