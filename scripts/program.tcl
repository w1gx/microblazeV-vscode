# Author: w1gx
# Date:   2026-11-22

lassign $argv bit url
source [file join [file dirname [info script]] hw_connect.tcl]

set dev [hw_open_device $url]
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device -update_hw_probes false $dev
if {[get_property REGISTER.IR.BIT5_DONE $dev] != 1} { error "program: DONE did not go high" }
puts "program: OK, FPGA configured"
hw_close
