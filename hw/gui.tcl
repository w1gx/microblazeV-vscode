# Author: w1gx
# Date:   2026-11-22
#
# Startup script for `make gui`: open the Vivado project (create it from
# hw/system_bd.tcl if there is none, or if FRESH=1) and add the toolbar
# commands for exporting the block design and building hardware + BSP.

source [file join [file dirname [info script]] project.tcl]

set xpr [file join $mbv::proj_dir mb_v.xpr]
if {[file exists $xpr] && !([info exists ::env(FRESH)] && $::env(FRESH) eq "1")} {
    open_project $xpr
    mbv::setup_project
    if {![mbv::bd_has_cells]} {
        # Empty or no block design (an earlier start was missing an IP): build it now.
        set missing [mbv::create_bd]
    } else {
        set missing ""
        if {![mbv::bd_matches_source]} {
            puts "WARNING: the block design in this project differs from hw/system_bd.tcl."
            puts "         Use 'MBV: Export BD' to keep the project version, or close Vivado"
            puts "         and run 'make gui FRESH=1' to recreate it from hw/system_bd.tcl."
        }
    }
} else {
    set missing [mbv::new_project]
}
if {$missing eq ""} {
    mbv::open_bd
} else {
    puts "WARNING: no block design yet - the IP catalog lacks: $missing"
    puts "         Add the repository with this IP in Settings > IP > Repository, then run"
    puts "         mbv::create_bd in the Tcl Console (or close Vivado and run make gui again)."
}

# Custom commands (Tools > Custom Commands and toolbar). Vivado stores them in
# the user settings, so they are recreated on every start.
set cmds {
    mbv_export_bd {MBV: Export BD}        {Write the block design to hw/system_bd.tcl}   export_bd.tcl export_bd.png
    mbv_build     {MBV: Build HW + BSP}   {Export, implement, write build/hw/out, generate the BSP} build.tcl build.png
}
foreach {name menu desc file icon} $cmds {
    catch {remove_gui_custom_commands $name}
    create_gui_custom_command -name $name -menu_name $menu -description $desc -show_on_toolbar \
        -tcl_file [file join $mbv::root hw gui $file] \
        -toolbar_icon [file join $mbv::root hw gui icons $icon]
}
puts "mbv: ready. Edit the block design, then use 'MBV: Build HW + BSP' (toolbar) and run make."
