# Author: w1gx
# Date:   2026-11-22
#
# Toolbar command "MBV: Export BD": write the block design to hw/system_bd.tcl.
source [file join [file dirname [info script]] .. project.tcl]
mbv::export_bd
