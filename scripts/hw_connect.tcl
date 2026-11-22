# Author: w1gx
# Date:   2026-11-22
#
# Shared by program.tcl and flash.tcl: open the first JTAG target and return
# the xc7a100t on it.
proc hw_open_device {url} {
    open_hw_manager
    if {$url eq ""} { connect_hw_server -allow_non_jtag } else { connect_hw_server -url $url -allow_non_jtag }
    set targets [get_hw_targets -quiet *]
    if {[llength $targets] == 0} {
        error "program: no JTAG target found - is the Arty plugged in and powered?"
    }
    current_hw_target [lindex $targets 0]
    open_hw_target
    set dev [lindex [get_hw_devices -quiet xc7a100t*] 0]
    if {$dev eq ""} { error "program: no xc7a100t on the JTAG chain ([get_hw_devices])" }
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    puts "program: target [lindex $targets 0], device $dev"
    return $dev
}

proc hw_close {} {
    catch close_hw_target
    catch disconnect_hw_server
    catch close_hw_manager
}
