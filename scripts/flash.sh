#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Write a bitstream to the Arty's quad-SPI flash so it boots at power-up.
#
#   scripts/flash.sh [file.bit [image.img]]
#
# Default for APP (default demo):
#   program in the local memory -> build/sw/$APP/download.bit
#   program in DDR (RUN_FROM=DDR, e.g. echo) -> the bootloader build/sw/boot/download.bit
#       at 0, plus build/sw/$APP/app.img at the offset from sw/common/mbv_image.h
#
# FLASH_PART: the flash chip on your board revision. Arty A7 rev D/E use a
# Spansion S25FL128S (default); older boards have a Micron N25Q128 /
# MT25QL128 - use FLASH_PART=mt25ql128-spi-x1_x2_x4 for those.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
: "${FLASH_PART:=s25fl128sxxxxxx0-spi-x1_x2_x4}"

IMG_OFFSET=$(sed -nE 's/^#define MBV_IMAGE_FLASH_OFFSET +(0x[0-9A-Fa-f]+)u.*/\1/p' "$ROOT/sw/common/mbv_image.h")
if [ $# -gt 0 ]; then
    BIT="$(realpath "$1")"; IMG="${2:+$(realpath "$2")}"
elif [ "$(make -s --no-print-directory -C "$ROOT/sw" APP="$APP" print-run-from)" = DDR ]; then
    BIT="$(realpath "$SW_OUT/boot/download.bit")"; IMG="$(realpath "$SW_OUT/$APP/app.img")"
else
    BIT="$(realpath "$SW_OUT/$APP/download.bit")"; IMG=""
fi
[ -f "$BIT" ] || { echo "flash: $BIT not found - run make flash (it builds what is needed)"; exit 1; }
[ -z "$IMG" ] || [ -f "$IMG" ] || { echo "flash: $IMG not found - run make flash APP=$APP"; exit 1; }
MCS="$SW_OUT/$APP/flash.mcs"

echo "flash: $BIT -> $FLASH_PART"
[ -z "$IMG" ] || echo "flash: + $IMG at $IMG_OFFSET (loaded into DDR by the bootloader)"
echo "flash: erase, program and verify over JTAG take about 3-5 minutes ..."
LOG="$ROOT/build/log/flash.log"
rm -f "$LOG"
vivado_batch "$ROOT/build/log" "$ROOT/scripts/flash.tcl" "$BIT" "$MCS" "$FLASH_PART" "${HW_SERVER_URL:-}" \
    "$IMG" "$IMG_OFFSET" > "$ROOT/build/log/flash.out" 2>&1 &
VPID=$!
# Show Vivado's progress lines while it runs (full log: build/log/flash.log);
# tail ends by itself when Vivado exits.
tail -n +1 -F --pid=$VPID "$LOG" 2>/dev/null | grep --line-buffered -E \
    '^(program|flash):|Mfg ID|Performing|successful|[Ff]ailed|^ERROR' | sed -u 's/^/  /' || true
rc=0; wait $VPID || rc=$?
if [ $rc -ne 0 ]; then
    echo "flash: FAILED, see $LOG"; tail -5 "$ROOT/build/log/flash.out"; exit 1
fi
echo "flash: done - the board now boots this bitstream at power-up (and with the PROG button)"
