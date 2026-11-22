# lwIP echo server

AMD's *lwIP Echo Server* application template (`main.c`, `echo.c`, `platform.c`,
`platform.h`) from `Vivado/data/embeddedsw/lib/sw_apps/lwip_echo_server`. MIT licensed
(see the file headers).

What this project adds:
- **`platform_config.h`:** replaces the template's CMake-generated `platform_config.h.in`.
- **`netinfo.c` / `netinfo.h`:** report the Ethernet configuration on the console.
- **`emaclite_rx.c` / `emaclite_rx.h`:** work around lost receive interrupts. AMD's Ethernet Lite
  driver hands only one frame to lwIP per interrupt, and with two frames waiting the second one
  got stuck. That showed as ~320 ms pings and stalled connections. The main loop now fetches
  waiting frames itself (0.5 ms pings).
- **`main.c`:** calls these from lines marked `/* mb-test */`. The last `netinfo` call replaces
  the template's `print_ip_settings()`. `echo.c`, `platform.c` and `platform.h` are unchanged.
- **`app.mk`:** `RUN_FROM := DDR`, and `-include xil_printf.h` because the template uses
  `xil_printf` without including its header.

Behaviour:
- Gets an address by DHCP and falls back to 192.168.1.10/24 (gateway 192.168.1.1)
  after about 12 s without a DHCP server.
- MAC address 00:0a:35:00:01:02 (`main.c`).
- Echoes everything sent to TCP port 7: `nc <board-ip> 7`.
- Prints its network configuration at startup (MAC, PHY and link, DHCP or fallback, IP, netmask,
  gateway, and the `nc` command to use).
- Runs from DDR (`app.mk`):
  - try it: `make run APP=echo` (through the debugger, gone after RESET)
  - keep it: `make flash APP=echo` (with the bootloader, starts at power-up and after RESET)
  - debug it: VS Code *Debug echo* (F5)
- IPv6 (`lwip220_ipv6_enable` in `sw/bsp.conf`) switches the template to an IPv6-only path with
  limits. See "IPv6" in the main README.
