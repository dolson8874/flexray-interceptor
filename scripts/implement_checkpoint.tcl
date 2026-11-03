# Constraint-only implementation restart; no bitstream or hardware access.
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[catch {
  set suffix [lindex $argv 1]
  set strategy [lindex $argv 2]
  if {$strategy eq ""} { set strategy scoped }
  set source_build [file join $repo tests design_[lindex $argv 0]${suffix}.sim]
  set build [file join $repo tests design_[lindex $argv 0]${suffix}_${strategy}.sim]
  file mkdir $build
  cd $build
  set_param general.maxThreads 4
  open_checkpoint [file join $source_build synthesized.dcp]
  read_xdc [file join $repo flexray-interceptor-vivado.srcs constrs_1 new control_snapshot_cdc.xdc]
  set first_stages [get_cells -hierarchical -filter {NAME =~ */control_snapshot_0/U0/request_meta_reg || NAME =~ */control_snapshot_0/U0/ack_meta_reg}]
  if {[llength $first_stages] != 2} { error "CDC constraints do not match both synchronizer stages" }
  opt_design
  if {$strategy eq "explore"} {
    place_design -directive Explore
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
  } else {
    place_design
    phys_opt_design
    route_design
  }
  report_timing_summary -max_paths 10 -report_unconstrained -file [file join $build timing_summary.rpt]
  report_bus_skew -file [file join $build bus_skew.rpt]
  set skew_file [open [file join $build bus_skew.rpt] r]
  set skew_report [read $skew_file]; close $skew_file
  if {[string first "VIOLATED" $skew_report] >= 0} { error "Bus skew constraints are not met" }
  report_cdc -details -file [file join $build cdc.rpt]
  report_methodology -file [file join $build methodology.rpt]
  report_drc -file [file join $build drc.rpt]
  report_utilization -file [file join $build utilization.rpt]
  write_checkpoint -force [file join $build routed.dcp]
  set setup [get_timing_paths -delay_type max -max_paths 1]
  set hold [get_timing_paths -delay_type min -max_paths 1]
  puts "IMPLEMENT_RESULT mode=[lindex $argv 0] WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold]"
  if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} { error "Setup/hold timing not met" }
  exit
} impl_error impl_opts]} {
  puts stderr "IMPLEMENT_ERROR: $impl_error"
  puts stderr [dict get $impl_opts -errorinfo]
  exit 1
}
