#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Load a bitstream into the FPGA over JTAG (lost at power-off; see flash.sh).
#
#   scripts/program.sh [file.bit]      default: build/sw/$APP/download.bit (hardware + program, APP=demo)
#
# HW_SERVER_URL=host:3121 to use a remote hw_server; default starts a local one.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

BIT="$(realpath "${1:-$SW_OUT/$APP/download.bit}")"
[ -f "$BIT" ] || { echo "program: $BIT not found - run make first (APP=$APP)."
    echo "         Programs that run from DDR have no download.bit: use make run APP=$APP."; exit 1; }

echo "program: $BIT"
vivado_batch "$ROOT/build/log" "$ROOT/scripts/program.tcl" "$BIT" "${HW_SERVER_URL:-}" > "$ROOT/build/log/program.out" 2>&1 \
    || { grep -E '^(ERROR|program:)' "$ROOT/build/log/program.log" || tail -20 "$ROOT/build/log/program.out"; exit 1; }
grep -h '^program:' "$ROOT/build/log/program.log"
