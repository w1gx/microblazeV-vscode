# Author: w1gx
# Date:   2026-11-22
#
# Batch hardware build: recreate the project from hw/system_bd.tcl, implement
# it and write build/hw/out:
#   system.bit       bitstream (local memory empty; sw/Makefile merges the ELF in)
#   system.mmi       BRAM map for updatemem
#   system.xsa       hardware handoff, input for the BSP (scripts/build_bsp.sh)
#   memory.ld        MEMORY {} block for the linker script
#   cpu.mk           -march/-mabi for this CPU configuration
#   *.rpt            utilization and timing
#
#   vivado -mode batch -source build_hw.tcl -tclargs <jobs> <force>
#
# Refuses to replace a project whose block design has changes that are not in
# hw/system_bd.tcl (GUI edits that were never exported), unless force is 1.
# Does nothing if build/hw/out already matches the sources (fingerprint),
# unless REBUILD=1.

lassign $argv jobs force
source [file join [file dirname [info script]] project.tcl]

set xpr [file join $mbv::proj_dir mb_v.xpr]
if {[file exists $xpr] && $force != 1} {
    open_project $xpr
    if {[catch {mbv::bd_matches_source} same]} { set same 1 }
    close_project
    if {!$same} {
        error "build/hw/proj has block design changes that are not in hw/system_bd.tcl.\
               Export them from the GUI (MBV: Export BD) or run with FORCE=1 to discard them."
    }
}

# Nothing to do if build/hw/out was built from exactly these sources.
if {![mbv::rebuild_requested] && [mbv::outputs_match [mbv::fingerprint]]} {
    puts "mbv: build/hw/out was already built from this design (fingerprint) - nothing to do"
    puts "mbv: (REBUILD=1 forces a full build)"
    mbv::confirm_outputs
    return
}

mbv::new_project
mbv::build $jobs
