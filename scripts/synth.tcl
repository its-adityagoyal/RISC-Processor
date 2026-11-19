# Vivado non-project implementation flow for one MiniRISC top level.
#
#   vivado -mode batch -source scripts/synth.tcl -tclargs <top> <period_ns> <outdir> <imem_hex> [generics|-]
#   generics: comma-separated NAME=VALUE overrides, e.g. BP_MODE=2
#
# Out-of-context synth -> opt -> place -> route on the Kintex-7 xc7k70t, then
# post-route timing and utilisation. Writes <outdir>/{timing,critical_path,
# util,lint}.rpt and <outdir>/summary.txt (one key=value line).
#
# Fmax: the register file writes on the FALLING edge, so the design has
# half-cycle paths (posedge->negedge, negedge->posedge) as well as full-cycle
# ones. The minimum period is the worst of
#     T - slack(rise->rise)        full-cycle paths
#     T - 2*slack(rise->fall)      half-cycle paths need delay <= T/2
#     T - 2*slack(fall->rise)
set top    [lindex $argv 0]
set period [lindex $argv 1]
set outdir [file normalize [lindex $argv 2]]
set imem   [lindex $argv 3]
set extra  [lindex $argv 4]
set part   xc7k70tfbv676-1
set proj   [file normalize [file join [file dirname [info script]] ..]]
file mkdir $outdir

read_verilog [glob [file join $proj rtl *.v]]

# synth_design -generic mis-parses paths that contain spaces, so the
# ROM image is copied into the run directory (run Vivado from a space-free dir).
set local_imem [file join [pwd] imem_init.hex]
file copy -force $imem $local_imem
set imem $local_imem

set generics [list -generic "IMEM_INIT_FILE=\"$imem\""]
# overrides arrive as NAME:VALUE (cmd.exe splits '=' when vivado.bat is called)
if {$extra ne "" && $extra ne "-"} {
    foreach g [split $extra ","] { lappend generics -generic [string map {: =} $g] }
}
puts "GENERICS: $generics"

# ---- lint (Vivado linter) ---------------------------------------------------
if {[catch {synth_design -top $top -part $part -lint {*}$generics} msg]} {
    puts "LINT: not available ($msg)"
}
close_design -quiet

# ---- implementation ---------------------------------------------------------
synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt {*}$generics
create_clock -name clk -period $period [get_ports clk]
# Out-of-context: model the clock as coming from a global buffer so the router
# estimates real clock skew (otherwise HD.CLK_SRC warnings, optimistic timing).
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
report_utilization -file $outdir/util_synth.rpt
opt_design
place_design
route_design

report_timing_summary -max_paths 10 -file $outdir/timing.rpt
report_timing -max_paths 3 -path_type full -file $outdir/critical_path.rpt
report_utilization -file $outdir/util.rpt

proc worst_slack {args} {
    set p [get_timing_paths -setup -max_paths 1 {*}$args]
    if {$p eq ""} { return "" }
    return [get_property SLACK $p]
}
set clk  [get_clocks clk]
set s_rr [worst_slack -rise_from $clk -rise_to $clk]
set s_rf [worst_slack -rise_from $clk -fall_to $clk]
set s_fr [worst_slack -fall_from $clk -rise_to $clk]
set s_ff [worst_slack -fall_from $clk -fall_to $clk]

set tmin 0.0
set crit "none"
foreach {s factor name} [list $s_rr 1 rise-rise $s_ff 1 fall-fall $s_rf 2 rise-fall $s_fr 2 fall-rise] {
    if {$s eq ""} { continue }
    set t [expr {$period - $factor * $s}]
    if {$t > $tmin} { set tmin $t; set crit $name }
}
set fmax [expr {1000.0 / $tmin}]

set util [report_utilization -return_string]
proc util_count {util label} {
    if {[regexp "\\|\\s*$label\\s*\\|\\s*(\\d+)" $util -> n]} { return $n }
    return 0
}
set luts   [util_count $util "Slice LUTs\\*?"]
set ffs    [util_count $util "Slice Registers"]
set lutram [util_count $util "LUT as Memory"]
set bram   [util_count $util "Block RAM Tile"]
set wns    [get_property SLACK [get_timing_paths -setup -max_paths 1]]

set line [format "SYNTH top=%s period=%.3f wns=%.3f slack_rr=%s slack_rf=%s slack_fr=%s slack_ff=%s tmin=%.3f fmax_mhz=%.1f critical=%s luts=%s ffs=%s lutram=%s bram=%s" \
          $top $period $wns $s_rr $s_rf $s_fr $s_ff $tmin $fmax $crit $luts $ffs $lutram $bram]
puts $line
set fh [open $outdir/summary.txt w]; puts $fh $line; close $fh
