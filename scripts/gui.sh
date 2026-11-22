#!/usr/bin/env bash
# Author: w1gx
# Date:   2026-11-22
#
# Open the hardware project in the Vivado GUI (created from hw/system_bd.tcl
# if there is none yet). Toolbar commands added by hw/gui.tcl:
#   MBV: Export BD          write the block design to hw/system_bd.tcl
#   MBV: Build HW + BSP     export, implement, write build/hw/out, generate the BSP
#
#   scripts/gui.sh            open (or create) build/hw/proj
#   FRESH=1 scripts/gui.sh    recreate it from hw/system_bd.tcl first (drops unexported edits)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
export FRESH="${FRESH:-0}"

# Vivado needs an X display. VS Code's Remote-SSH terminals usually have none,
# so fall back to a working display of another session of this user (e.g. an
# ssh -X terminal). The window then appears wherever that session's X server is.
display_ok() { DISPLAY="$1" timeout 5 xset q > /dev/null 2>&1; }
if [ -z "${DISPLAY:-}" ] || ! display_ok "$DISPLAY"; then
    found=""
    for d in $(for p in $(pgrep -u "$USER"); do
                   { tr '\0' '\n' < /proc/$p/environ; } 2>/dev/null | sed -n 's/^DISPLAY=//p'
               done | sort -u); do
        if display_ok "$d"; then found=$d; break; fi
    done
    if [ -z "$found" ]; then
        echo "gui: no X display available (DISPLAY=${DISPLAY:-<unset>})."
        echo "     Open an X11-forwarding ssh session to this machine (ssh -X / -Y, or MobaXterm),"
        echo "     or enable X11 forwarding for VS Code Remote-SSH (see README, VS Code section)."
        exit 1
    fi
    echo "gui: DISPLAY=${DISPLAY:-<unset>} doesn't work here, using $found from another session."
    echo "     Vivado closes if that session ends."
    export DISPLAY=$found
fi
LOG="$ROOT/build/hw/gui"
mkdir -p "$LOG"
cd "$LOG"
rm -f "$LOG/vivado.log" "$LOG/console.log"   # the wait below must not see an old "ready"
nohup "$VIVADO" -mode gui -notrace -log "$LOG/vivado.log" -journal "$LOG/vivado.jou" \
    -source "$ROOT/hw/gui.tcl" > "$LOG/console.log" 2>&1 &
pid=$!
echo "gui: Vivado starting (pid $pid, log $LOG/vivado.log) ..."

# Wait until hw/gui.tcl reports ready, so a failed start doesn't go unnoticed.
for _ in $(seq 1 120); do
    if grep -q '^mbv: ready' "$LOG/vivado.log" 2>/dev/null; then
        grep -h '^WARNING: the block design' -A2 "$LOG/vivado.log" || true
        echo "gui: Vivado is up with build/hw/proj open."
        exit 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "gui: Vivado exited during startup:"
        grep -hE 'ERROR|Abnormal|terminate called|Display test' "$LOG/console.log" | head -5
        ls "$LOG"/hs_err_pid*.log 2>/dev/null | tail -1 | sed 's/^/     crash report: /'
        echo "     This has been seen once as a transient X11 error over ssh forwarding - try again."
        exit 1
    fi
    sleep 1
done
echo "gui: Vivado is still starting after 2 minutes - check $LOG/vivado.log"
