#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Generate and build the board support package (BSP) for the current hardware
# with AMD's command-line tools shipped in Vivado (no Vitis IDE):
#
#   system.xsa --sdtgen--> system device tree --empyro--> drivers + standalone
#   runtime + libraries, compiled into build/bsp/domain/lib/*.a
#
# Drivers: one per IP in the design, picked automatically (GPIO, UART Lite,
# INTC, ...), with xparameters.h and the driver config tables.
# Libraries: whatever sw/bsp.conf lists, plus lwip220 when the design has an
# Ethernet MAC (AUTO_LWIP=1).
#
# Runs at the end of hw/build_hw.sh; run it by hand after editing sw/bsp.conf.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
: "${SDTGEN:=$XILINX_ROOT/Vivado/bin/sdtgen}"
: "${EMPYRO:=$XILINX_ROOT/Vivado/bin/empyro}"
: "${PROC:=microblaze_riscv_0}"

XSA="$HW_OUT/system.xsa"
[ -f "$XSA" ] || { echo "build_bsp: $XSA not found - run hw/build_hw.sh first"; exit 1; }

BSP_LIBS=""; AUTO_LWIP=1; BSP_LIB_OPTIONS=""
[ -f "$ROOT/sw/bsp.conf" ] && source "$ROOT/sw/bsp.conf"

BSP="$ROOT/build/bsp"
LOG="$BSP/build_bsp.log"
rm -rf "$BSP"
mkdir -p "$BSP"
: > "$LOG"
step() {   # step <description> <command...>
    local what=$1; shift
    echo "== $what: $*" >> "$LOG"
    (cd "$BSP" && "$@") >> "$LOG" 2>&1 || {
        echo "build_bsp: $what FAILED, see $LOG"; grep -E 'ERROR|Error|error:' "$LOG" | tail -10; exit 1; }
}

step "device tree" "$SDTGEN" -eval "set_dt_param -xsa {$XSA} -dir {$BSP/sdt}; generate_sdt"
step "create BSP"  "$EMPYRO" create_bsp -s "$BSP/sdt/system-top.dts" -p "$PROC" \
                             -t empty_application -w "$BSP/domain"

libs="$BSP_LIBS"
if [ "$AUTO_LWIP" = 1 ] && grep -qE '"xlnx,(xps-ethernetlite|axi-ethernet)' "$BSP/sdt/pl.dtsi"; then
    case " $libs " in *" lwip220 "*) ;; *) libs="$libs lwip220";; esac
    echo "build_bsp: Ethernet MAC found -> adding lwip220"
fi
# shellcheck disable=SC2086
[ -n "${libs// }" ] && step "add libraries" "$EMPYRO" config_bsp -d "$BSP/domain" -al $libs
while read -r line; do
    [ -n "${line// }" ] || continue
    # shellcheck disable=SC2086
    step "library options" "$EMPYRO" config_bsp -d "$BSP/domain" -st $line
done <<< "$BSP_LIB_OPTIONS"

step "build BSP" "$EMPYRO" build_bsp -d "$BSP/domain"

drivers=$(cd "$BSP/domain/libsrc" && for d in */; do d=${d%/}; [ -d "$d/src" ] && [ "$d" != standalone ] && [ "$d" != common ] && [ "$d" != build_configs ] && echo "$d"; done | grep -v -E "^($(echo xiltimer $libs | tr ' ' '|'))$" | xargs)
echo "build_bsp: drivers:   ${drivers:-none}"
echo "build_bsp: libraries: standalone xiltimer$libs"
echo "build_bsp: done -> $BSP/domain (include/, lib/)"
