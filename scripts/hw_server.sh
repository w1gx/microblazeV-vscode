#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Make sure AMD's hw_server (JTAG access + GDB servers) is running. It is
# normally started by Vivado/xsdb (make program/run); a debugger that only
# attaches needs it too. GDB ports: 3004 = RISC-V 32-bit (MicroBlaze V).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
if pgrep -x hw_server > /dev/null; then
    echo "hw_server: already running"
else
    "$XILINX_ROOT/Vivado/bin/hw_server" -d -s TCP:127.0.0.1:3121 > /dev/null
    for _ in $(seq 1 20); do ss -ltn 2>/dev/null | grep -q ':3004 ' && break; sleep 0.5; done
    echo "hw_server: started (JTAG on 3121, GDB for RISC-V on 3004)"
fi
