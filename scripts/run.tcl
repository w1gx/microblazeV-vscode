# Author: w1gx
# Date:   2026-11-22
#
# xsdb script: [configure FPGA,] reset the MicroBlaze V, download the ELF, run.
lassign $argv elf bit start
if {$start eq ""} { set start 1 }

connect
if {$bit ne ""} {
    if {[catch {targets -set -nocase -filter {name =~ "xc7a100t*"}}]} {
        puts "run: no xc7a100t found over JTAG - is the Arty plugged in and powered? Targets are:"
        puts [targets]
        exit 1
    }
    puts "run: configuring the FPGA with $bit"
    fpga -file $bit
    after 500
}
# MicroBlaze V shows up as a hart under the debug module.
if {[catch {targets -set -nocase -filter {name =~ "*hart*" || name =~ "*microblaze*"}}]} {
    puts "run: no MicroBlaze V target found. Targets are:"
    puts [targets]
    exit 1
}
puts "run: target [targets -target-properties]"
catch {stop}
rst -processor
dow $elf
if {$start} {
    con
    puts "run: $elf running"
} else {
    puts "run: $elf loaded, CPU halted at [string trim [rrd pc]] - attach the debugger (GDB: localhost:3004)"
}
disconnect
