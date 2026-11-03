# Read-only check of the actual saved project, source list, BD defaults/wiring.
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[catch {
  open_project -read_only [file join $repo flexray-interceptor-vivado.xpr]
  foreach name {control_snapshot.vhd flexray_can_queue.vhd flexray_can_telemetry.vhd flexray_log_dispatch.vhd can_tx.vhd} {
    set source [get_files -all $name]
    if {[llength $source] != 1 || ![get_property USED_IN_SYNTHESIS $source]} { error "Missing enabled source: $name" }
  }
  set cdc [get_files -all control_snapshot_cdc.xdc]
  if {[llength $cdc] != 1 || [get_property USED_IN_SYNTHESIS $cdc] || ![get_property USED_IN_IMPLEMENTATION $cdc]} {
    error "Control CDC file must be enabled only for implementation"
  }
  open_bd_design [get_files bendbeam.bd]
  set hdl_file [open [file join $repo flexray-interceptor-vivado.srcs sources_1 imports flexray-interceptor-dolson8874 flexray_torque_intercept.vhd] r]
  set hdl_text [read $hdl_file]; close $hdl_file
  if {![regexp {constant\s+TEST_LCA\s*:\s*boolean\s*:=\s*false} $hdl_text]} { error "LCA test patches must remain disabled" }
  if {[get_property CONFIG.ENABLED [get_bd_cells flexray_can_telemetry_0]] ne "false" ||
      [get_property CONFIG.ENABLE_CAN_TELEMETRY [get_bd_cells joystick_decoder_0]] ne "false"} {
    error "Saved telemetry defaults are not disabled"
  }
  foreach signal {torque sign enable} {
    set expected [get_bd_nets -of_objects [get_bd_pins control_snapshot_0/${signal}_out]]
    set actual [get_bd_nets -of_objects [get_bd_pins flexray_torque_inter_0/$signal]]
    if {$expected ne $actual} { error "Control mailbox bypassed for $signal" }
  }
  puts "SAVED_PROJECT_PASS sources=enabled CDC=implementation_only telemetry=disabled controls=mailbox"
  close_project
  exit
} project_error project_opts]} {
  puts stderr "SAVED_PROJECT_ERROR: $project_error"
  puts stderr [dict get $project_opts -errorinfo]
  exit 1
}
