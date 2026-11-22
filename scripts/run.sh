#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Load an ELF through the debug module (MDM) with xsdb and start it, without
# touching the bitstream. Use this for programs that live in DDR, or to
# iterate without rewriting the bitstream.
#
#   scripts/run.sh [-p] [-s] [app.elf]   default: build/sw/$APP/app.elf (APP=demo)
#     -p   first configure the FPGA with build/hw/out/system.bit
#     -s   load but do not start: the CPU stays halted at the entry point, for a
#          debugger to attach (GDB on hw_server port 3004, see .vscode/launch.json)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

BIT=""; START=1
while [ $# -gt 0 ]; do
    case "$1" in
        -p) BIT="$HW_OUT/system.bit"; shift ;;
        -s) START=0; shift ;;
        *)  break ;;
    esac
done
ELF="$(realpath "${1:-$SW_OUT/$APP/app.elf}")"
[ -f "$ELF" ] || { echo "run: $ELF not found - run make first"; exit 1; }

mkdir -p "$ROOT/build/log"
"$XSDB" "$ROOT/scripts/run.tcl" "$ELF" "$BIT" "$START" 2>&1 | tee "$ROOT/build/log/run.log"
