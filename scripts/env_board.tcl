# Author: w1gx
# Date:   2026-11-22
#
# Make the Digilent board files visible to batch Vivado (BOARD_REPO from scripts/env.sh).
if {[info exists ::env(BOARD_REPO)] && $::env(BOARD_REPO) ne ""} {
    set_param board.repoPaths [list $::env(BOARD_REPO)]
} else {
    set_param board.repoPaths [list [file normalize ~/.Xilinx/Vivado/[version -short]/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/[version -short]/boards]]
}
