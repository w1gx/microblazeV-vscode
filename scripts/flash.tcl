# Author: w1gx
# Date:   2026-11-22

lassign $argv bit mcs part url data data_offset
source [file join [file dirname [info script]] hw_connect.tcl]

# 16 MB flash, x4. The bitstream already has SPI_BUSWIDTH 4 (hw/arty_a7_100.xdc).
# Optional second file: the DDR program image for the bootloader (sw/common/mbv_image.h).
set extra {}
if {$data ne ""} { set extra [list -loaddata "up $data_offset $data"] }
write_cfgmem -force -format mcs -size 16 -interface SPIx4 -loadbit "up 0x00000000 $bit" {*}$extra -file $mcs
puts "flash: wrote $mcs"

set dev [hw_open_device $url]
set mem_part [lindex [get_cfgmem_parts -quiet $part] 0]
if {$mem_part eq ""} { error "flash: unknown flash part '$part'" }
set mem [create_hw_cfgmem -hw_device $dev -mem_dev $mem_part]
set_property PROGRAM.FILES          [list $mcs] $mem
set_property PROGRAM.ADDRESS_RANGE  use_file    $mem
set_property PROGRAM.UNUSED_PIN_TERMINATION pull-none $mem
set_property PROGRAM.BLANK_CHECK    0 $mem
set_property PROGRAM.ERASE          1 $mem
set_property PROGRAM.CFG_PROGRAM    1 $mem
set_property PROGRAM.VERIFY         1 $mem
set_property PROGRAM.CHECKSUM       0 $mem

# The FPGA needs Vivado's flash-loader bitstream to reach the SPI pins.
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem -hw_cfgmem $mem
puts "flash: programmed and verified"

# Reconfigure from flash, as at power-up.
boot_hw_device $dev
puts "flash: FPGA rebooted from flash"
hw_close
