# Author: w1gx
# Date:   2026-11-22
#
# Toolbar command "MBV: Build HW + BSP": export the block design, implement
# the open project, write build/hw/out and generate the BSP. Afterwards run
# `make` (or the VS Code build task) for the software.
source [file join [file dirname [info script]] .. project.tcl]
set jobs [expr {[info exists ::env(JOBS)] ? $::env(JOBS) : 4}]
mbv::export_bd
mbv::build $jobs
mbv::bsp
puts "mbv: hardware and BSP done - run make for the software"
