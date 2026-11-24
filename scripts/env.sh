# Author: w1gx
# Date:   2026-11-22
#
# Shared settings for the build scripts. Override any of these from the environment.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${XILINX_ROOT:=/opt/Xilinx/2026.1}"
: "${VIVADO:=$XILINX_ROOT/Vivado/bin/vivado}"
: "${XSDB:=$XILINX_ROOT/Vivado/bin/xsdb}"
: "${UPDATEMEM:=$XILINX_ROOT/Vivado/bin/updatemem}"
: "${BOARD_REPO:=$HOME/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards}"
# Optional: user IP repositories (colon-separated) added to every project, for
# custom IP in the block design. Repositories set in the GUI (Settings > IP >
# Repository) are kept when the project is recreated, so this is only needed
# for a project created without one, e.g. a batch `make hw` after deleting build/.
: "${IP_REPO:=}"
: "${JOBS:=4}"
: "${HW_OUT:=$ROOT/build/hw/out}"
: "${SW_OUT:=$ROOT/build/sw}"
: "${APP:=demo}"                 # program in sw/apps/<APP>, built into $SW_OUT/<APP>
export BOARD_REPO IP_REPO JOBS     # read by the Vivado Tcl scripts
# Vivado in batch mode, quiet console, logs next to the outputs.
vivado_batch() {   # vivado_batch <logdir> <script.tcl> [tclargs...]
    local logdir=$1 script=$2; shift 2
    mkdir -p "$logdir"
    (cd "$logdir" && "$VIVADO" -mode batch -notrace -nojournal -log "$logdir/$(basename "$script" .tcl).log" \
        -source "$script" ${1:+-tclargs "$@"})
}
mkdir -p "$ROOT/build/log"
