# Author: w1gx
# Date:   2026-11-22
#
# Project procedures shared by the batch build (build_hw.tcl) and the GUI
# (gui.tcl and the custom toolbar commands in hw/gui/).
#
# hw/system_bd.tcl is the source of the block design; the Vivado project in
# build/hw/proj is generated from it and can be edited in the GUI. GUI edits
# are written back with mbv::export_bd.

namespace eval mbv {
    variable root       [file normalize [file join [file dirname [info script]] ..]]
    variable part       xc7a100tcsg324-1
    variable board_part digilentinc.com:arty-a7-100:part0:1.1
    variable proj_dir   [file join $root build hw proj]
    variable out_dir    [file join $root build hw out]
    variable bd_src     [file join $root hw system_bd.tcl]
    variable xdc        [file join $root hw arty_a7_100.xdc]
    variable cpu        microblaze_riscv_0
    # Synthesized IP survives project recreation here (make hw, make gui FRESH=1).
    variable ipcache    [file join $root build hw ipcache]
    # Fingerprint of the sources build/hw/out was built from (see mbv::fingerprint).
    variable fp_file    [file join $out_dir source.fingerprint]
    variable outputs    {system.bit system.mmi system.xsa memory.ld cpu.mk}
}
source [file join $mbv::root scripts env_board.tcl]
source [file join $mbv::root hw gen_memmap.tcl]

# Fresh project from hw/system_bd.tcl + hw/arty_a7_100.xdc (no implementation).
proc mbv::new_project {} {
    variable root; variable part; variable board_part; variable proj_dir; variable bd_src
    catch ::close_project
    file delete -force $proj_dir
    ::create_project mb_v $proj_dir -part $part
    mbv::setup_project
    if {[catch {set_property board_part $board_part [current_project]}] ||
        [get_property board_part [current_project]] eq ""} {
        error "Board part $board_part not found. Set BOARD_REPO to the directory that holds the Digilent board files."
    }
    set_property target_language VHDL [current_project]
    add_files -fileset constrs_1 $mbv::xdc

    source $bd_src
    cr_bd_system ""
    if {[get_files -quiet system.bd] eq ""} { error "Block design creation failed" }
    add_files -norecurse [make_wrapper -files [get_files system.bd] -top]
    set_property top system_wrapper [current_fileset]
    puts "mbv: created project [file join $proj_dir mb_v.xpr] from hw/system_bd.tcl"
}

# Project settings that are not part of the block design: the shared IP cache.
proc mbv::setup_project {} {
    variable ipcache
    file mkdir $ipcache
    set_property IP_OUTPUT_REPO $ipcache [current_project]
    set_property IP_CACHE_PERMISSIONS {read write} [current_project]
}

proc mbv::open_bd {} {
    if {[current_bd_design -quiet] eq ""} { open_bd_design [get_files system.bd] }
    return [current_bd_design]
}

# write_bd_tcl output without comments and blank lines, for comparing.
proc mbv::_bd_body {file} {
    set fh [open $file r]; set lines [split [read $fh] \n]; close $fh
    return [join [lsearch -all -inline -not -regexp $lines {^\s*(#.*)?$}] \n]
}

proc mbv::_export_tmp {} {
    variable root
    mbv::open_bd
    set tmp [file join $root build hw system_bd.export.tcl]
    write_bd_tcl -force -no_project_wrapper $tmp
    return $tmp
}

# 1 if the project's block design is the same as hw/system_bd.tcl.
proc mbv::bd_matches_source {} {
    variable bd_src
    set tmp [mbv::_export_tmp]
    set same [expr {[mbv::_bd_body $tmp] eq [mbv::_bd_body $bd_src]}]
    file delete $tmp
    return $same
}

# Validate, save and write the block design back to hw/system_bd.tcl.
proc mbv::export_bd {} {
    variable bd_src
    mbv::open_bd
    validate_bd_design
    save_bd_design
    set tmp [mbv::_export_tmp]
    if {[mbv::_bd_body $tmp] eq [mbv::_bd_body $bd_src]} {
        file delete $tmp
        puts "mbv: hw/system_bd.tcl is up to date"
        return 0
    }
    file rename -force $tmp $bd_src
    puts "mbv: exported block design to hw/system_bd.tcl (commit it to keep the change)"
    return 1
}

# SHA-256 over everything the hardware outputs depend on: block design and
# constraints (comments and blank lines ignored), part, board, Vivado version.
proc mbv::fingerprint {} {
    variable root; variable bd_src; variable xdc; variable part; variable board_part
    set tmp [file join $root build hw fingerprint.tmp]
    set fh [open $tmp w]
    puts $fh "vivado [version -short]\npart $part\nboard $board_part"
    puts $fh "--- system_bd.tcl\n[mbv::_bd_body $bd_src]"
    puts $fh "--- xdc\n[mbv::_bd_body $xdc]"
    close $fh
    set fp [lindex [exec sha256sum $tmp] 0]
    file delete $tmp
    return $fp
}

# 1 if build/hw/out is complete and was built from sources with this fingerprint.
proc mbv::outputs_match {fp} {
    variable out_dir; variable fp_file; variable outputs
    foreach f $outputs { if {![file exists [file join $out_dir $f]]} { return 0 } }
    if {![file exists $fp_file]} { return 0 }
    set fh [open $fp_file r]; set old [string trim [read $fh]]; close $fh
    return [expr {$old eq $fp}]
}

proc mbv::rebuild_requested {} {
    return [expr {[info exists ::env(REBUILD)] && $::env(REBUILD) eq "1"}]
}

# Implement the open project and write everything the software needs to
# build/hw/out. Works on a fresh batch project and on one edited in the GUI.
# Skips implementation when build/hw/out already matches the sources
# (fingerprint), unless REBUILD=1.
proc mbv::build {{jobs 4}} {
    variable out_dir; variable cpu; variable fp_file
    file mkdir $out_dir

    mbv::open_bd
    gen_memmap $cpu [file join $out_dir memory.ld] [file join $out_dir cpu.mk]

    set fp [mbv::fingerprint]
    set impl [get_runs impl_1]
    if {[get_property PROGRESS $impl] eq "100%" && ![get_property NEEDS_REFRESH $impl]} {
        puts "mbv: implementation is up to date"
    } elseif {![mbv::rebuild_requested] && [mbv::outputs_match $fp]} {
        puts "mbv: build/hw/out was already built from this design (fingerprint) - skipping implementation"
        puts "mbv: (REBUILD=1 forces a full build)"
        return
    } else {
        file delete -force $fp_file
        reset_run synth_1
        launch_runs impl_1 -to_step write_bitstream -jobs $jobs
        wait_on_run impl_1
        if {[get_property PROGRESS $impl] ne "100%"} {
            error "Implementation failed: [get_property STATUS $impl]"
        }
    }

    open_run impl_1
    write_mem_info -force [file join $out_dir system.mmi]
    report_utilization    -file [file join $out_dir utilization.rpt]
    report_timing_summary -file [file join $out_dir timing.rpt]
    set bit [file join [get_property DIRECTORY $impl] system_wrapper.bit]
    file copy -force $bit [file join $out_dir system.bit]
    write_hw_platform -fixed -include_bit -force -file [file join $out_dir system.xsa]

    set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    close_design
    set fh [open $fp_file w]; puts $fh $fp; close $fh
    puts "BUILD_HW_RESULT wns=$wns whs=$whs"
    if {$wns < 0 || $whs < 0} { puts "WARNING: timing not met" }
}

# Generate the BSP for the new hardware, only if system.xsa, sw/bsp.conf or
# scripts/build_bsp.sh changed (the `make bsp` target decides).
proc mbv::bsp {} {
    variable root
    if {[catch {exec make -C $root --no-print-directory bsp 2>@1} out]} {
        puts $out
        error "BSP generation failed"
    }
    if {[regexp {Nothing to be done|is up to date} $out]} {
        puts "mbv: BSP is up to date"
    } else {
        puts $out
    }
}
