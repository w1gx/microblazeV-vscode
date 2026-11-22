#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Rebuild the hardware from hw/system_bd.tcl + hw/arty_a7_100.xdc.
# Outputs land in build/hw/out (bitstream, .mmi, .xsa, memory.ld, cpu.mk), then
# scripts/build_bsp.sh generates the drivers/BSP for the new hardware in build/bsp.
#
# The project in build/hw/proj is recreated from hw/system_bd.tcl. If it holds
# GUI edits that were never exported, the build stops; FORCE=1 discards them.
# If build/hw/out already matches the sources (fingerprint) it does nothing;
# REBUILD=1 forces a full build. Synthesized IP is cached in build/hw/ipcache.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/env.sh"

OUT="$(dirname "$HW_OUT")"
mkdir -p "$OUT"
exec 9> "$OUT/.build_hw.lock"
if ! flock -n 9; then
    echo "build_hw: another hardware build is already running (lock $OUT/.build_hw.lock)."
    exit 1
fi
if pgrep -f "$ROOT/hw/gui.tcl" > /dev/null; then
    echo "build_hw: the project is open in the Vivado GUI (make gui)."
    echo "          Use its 'MBV: Build HW + BSP' button, or close Vivado first."
    exit 1
fi
mkdir -p "$HW_OUT"
echo "build_hw: building in $OUT (log: $OUT/build_hw.log) ..."
start=$(date +%s)
vivado_batch "$OUT" "$ROOT/hw/build_hw.tcl" "$JOBS" "${FORCE:-0}" > "$OUT/console.log" 2>&1 || {
    echo "build_hw: FAILED, see $OUT/build_hw.log"; grep -E '^(ERROR|CRITICAL WARNING)|^build/hw/proj has block design changes' "$OUT/build_hw.log" | head -20; exit 1; }
# console.log is this run's own output (Vivado may rotate build_hw.log).
grep -hE '^(BUILD_HW_RESULT|mbv: build/hw/out|mbv: \(REBUILD)' "$OUT/console.log" | sed 's/^/build_hw: /' || true
if grep -q 'WARNING: timing not met' "$OUT/console.log"; then echo "build_hw: WARNING: timing not met"; fi
echo "build_hw: done in $(( ($(date +%s) - start) / 60 )) min -> $HW_OUT"
# BSP only if the hardware file (or sw/bsp.conf) changed
make -C "$ROOT" --no-print-directory bsp
