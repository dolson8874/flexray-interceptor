# Inspect a completed local verification checkpoint without rerunning the build.
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[catch {
  set build [file join $repo tests design_[lindex $argv 0].sim]
  cd $build
  set_param general.maxThreads 4
  open_checkpoint [file join $build routed.dcp]
  set first_stages [get_cells -hierarchical -filter {NAME =~ */control_snapshot_0/U0/request_meta_reg || NAME =~ */control_snapshot_0/U0/ack_meta_reg}]
  set held [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/held_data_reg*}]
  set delivered [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/delivered_data_reg*}]
  if {[llength $first_stages] != 2 || [llength $held] == 0 || [llength $delivered] == 0} {
    error "The checkpoint does not contain the complete control mailbox"
  }
  report_bus_skew -file [file join $build bus_skew.rpt]
  set skew_file [open [file join $build bus_skew.rpt] r]
  set skew_report [read $skew_file]; close $skew_file
  if {[string first "VIOLATED" $skew_report] >= 0} { error "Bus skew constraints are not met" }
  report_exceptions -coverage -file [file join $build exception_coverage.rpt]
  report_timing -from $held -to $delivered -max_paths 24 -file [file join $build control_data_timing.rpt]
  set setup [get_timing_paths -delay_type max -max_paths 1]
  set hold [get_timing_paths -delay_type min -max_paths 1]
  puts "ROUTED_CDC_RESULT first_stages=[llength $first_stages] held_bits=[llength $held] delivered_bits=[llength $delivered] WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold]"
  exit
} check_error check_opts]} {
  puts stderr "ROUTED_CDC_ERROR: $check_error"
  puts stderr [dict get $check_opts -errorinfo]
  exit 1
}
