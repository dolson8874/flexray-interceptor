# Local-only Vivado 2024.2 validation. Does not generate/program a bitstream.
# argv: 0 = frame telemetry disabled, 1 = enabled (verification only).
#       Diagnostic CAN 0x1FA is enabled in both configurations.
#       prepare = refresh/copy the saved BD, skip synthesis/implementation.
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[catch {
set mode [lindex $argv 0]
if {$mode eq ""} { set mode 0 }
set build [file join $repo tests design_${mode}[lindex $argv 1].sim]
file mkdir $build
cd $build
set_param general.maxThreads 4
create_project -force local_verify [file join $build project] -part xa7s50csga324-1Q
set_property target_language VHDL [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO} [current_project]
set sources [file join $repo flexray-interceptor-vivado.srcs sources_1]
add_files -norecurse [glob [file join $sources imports flexray-interceptor-dolson8874 *.vhd]]
add_files -norecurse [glob [file join $sources new *.vhd]]
set_property file_type {VHDL 2008} [get_files flexray_can_queue.vhd]
set input_dir [file join $build input_[clock seconds]]
file mkdir $input_dir
file mkdir [file join $input_dir bendbeam]
file copy -force {*}[glob [file join $sources bd bendbeam *]] [file join $input_dir bendbeam]
file mkdir [file join $input_dir fifo_generator_0]
file copy -force [file join $sources ip fifo_generator_0 fifo_generator_0.xci] [file join $input_dir fifo_generator_0]
# Relocate the generation roots embedded in the copied source descriptors.
set copied_files [concat [glob [file join $input_dir bendbeam *.bd]] [glob [file join $input_dir bendbeam ip * *.xci]] [glob [file join $input_dir fifo_generator_0 *.xci]]]
foreach descriptor $copied_files {
  set channel [open $descriptor r]; set contents [read $channel]; close $channel
  regsub -all {"gen_directory": "[^"]*"} $contents "\"gen_directory\": \"[file join $build generated [file rootname [file tail $descriptor]]]\"" contents
  set channel [open $descriptor w]; puts -nonewline $channel $contents; close $channel
}
import_ip -files [file join $input_dir fifo_generator_0 fifo_generator_0.xci]
import_files -norecurse [file join $input_dir bendbeam bendbeam.bd]
set active_bd [get_property NAME [get_files bendbeam.bd]]
set_property synth_checkpoint_mode None [get_files bendbeam.bd]
set_property generate_synth_checkpoint false [get_files fifo_generator_0.xci]
update_compile_order -fileset sources_1
open_bd_design [get_files bendbeam.bd]
puts "REFRESH_MODULE_START"
if {[llength [get_bd_pins -quiet joystick_decoder_0/telemetry_valid]] == 0} {
set connections {}
foreach pin [get_bd_pins -of_objects [get_bd_cells joystick_decoder_0]] {
  set net [get_bd_nets -quiet -of_objects $pin]
  if {[llength $net]} { lappend connections [list [file tail $pin] $net] }
}
delete_bd_objs [get_bd_cells joystick_decoder_0]
create_bd_cell -type module -reference joystick_decoder joystick_decoder_0
foreach connection $connections {
  connect_bd_net -net [lindex $connection 1] [get_bd_pins joystick_decoder_0/[lindex $connection 0]]
}
}
puts "REFRESH_MODULE_DONE"
proc refresh_logging_reference {name reference} {
  set connections {}
  set configuration {}
  foreach parameter {ENABLED CAN_ID PERIOD_CYCLES MAX_AGE_CYCLES} {
    if {[lsearch -exact [list_property [get_bd_cells $name]] CONFIG.$parameter] >= 0} {
      lappend configuration CONFIG.$parameter [get_property CONFIG.$parameter [get_bd_cells $name]]
    }
  }
  foreach pin [get_bd_pins -of_objects [get_bd_cells $name]] {
    set net [get_bd_nets -quiet -of_objects $pin]
    if {[llength $net]} { lappend connections [list [file tail $pin] $net] }
  }
  delete_bd_objs [get_bd_cells $name]
  create_bd_cell -type module -reference $reference $name
  if {[llength $configuration]} { set_property -dict $configuration [get_bd_cells $name] }
  foreach connection $connections {
    connect_bd_net -net [lindex $connection 1] [get_bd_pins $name/[lindex $connection 0]]
  }
}
if {[llength [get_bd_pins -quiet flexray_interceptor_0/log_stats]] == 0 ||
    [get_property LEFT [get_bd_pins flexray_interceptor_0/log_stats]] != 383} {
  refresh_logging_reference flexray_interceptor_0 flexray_interceptor
}
if {[llength [get_bd_cells -quiet flexray_log_can_diagnostics_0]] &&
    [get_property LEFT [get_bd_pins flexray_log_can_diagnostics_0/stats]] != 383} {
  refresh_logging_reference flexray_log_can_diagnostics_0 flexray_log_can_diagnostics
}
if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins flexray_interceptor_0/spi_byte_done]]] == 0} {
  connect_bd_net [get_bd_pins SPI_SLAVE_0/DOUT_VLD] [get_bd_pins flexray_interceptor_0/spi_byte_done]
}
if {[llength [get_bd_cells -quiet flexray_can_telemetry_0]] == 0} {
  create_bd_cell -type module -reference flexray_can_telemetry flexray_can_telemetry_0
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins flexray_can_telemetry_0/src_clk]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins flexray_can_telemetry_0/dst_clk]
  connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins flexray_can_telemetry_0/rst]
  connect_bd_net [get_bd_pins flexray_interceptor_0/rx] [get_bd_pins flexray_can_telemetry_0/rx]
  connect_bd_net [get_bd_pins flexray_can_telemetry_0/m_valid] [get_bd_pins joystick_decoder_0/telemetry_valid]
  connect_bd_net [get_bd_pins flexray_can_telemetry_0/m_data] [get_bd_pins joystick_decoder_0/telemetry_data]
  connect_bd_net [get_bd_pins joystick_decoder_0/telemetry_ready] [get_bd_pins flexray_can_telemetry_0/m_ready]
}
if {$mode eq "1"} { set enabled true } else { set enabled false }
if {[llength [get_bd_cells -quiet flexray_log_can_diagnostics_0]] == 0} {
  create_bd_cell -type module -reference flexray_log_can_diagnostics flexray_log_can_diagnostics_0
  create_bd_cell -type module -reference can_telemetry_mux can_telemetry_mux_0
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins flexray_log_can_diagnostics_0/src_clk]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins flexray_log_can_diagnostics_0/dst_clk] [get_bd_pins can_telemetry_mux_0/clk]
  connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins flexray_log_can_diagnostics_0/rst] [get_bd_pins can_telemetry_mux_0/rst]
  connect_bd_net [get_bd_pins flexray_interceptor_0/log_stats] [get_bd_pins flexray_log_can_diagnostics_0/stats]
  foreach signal {valid data} {
    disconnect_bd_net [get_bd_nets -of_objects [get_bd_pins joystick_decoder_0/telemetry_$signal]] [get_bd_pins joystick_decoder_0/telemetry_$signal]
    connect_bd_net [get_bd_pins flexray_can_telemetry_0/m_$signal] [get_bd_pins can_telemetry_mux_0/a_$signal]
    connect_bd_net [get_bd_pins flexray_log_can_diagnostics_0/m_$signal] [get_bd_pins can_telemetry_mux_0/b_$signal]
    connect_bd_net [get_bd_pins can_telemetry_mux_0/m_$signal] [get_bd_pins joystick_decoder_0/telemetry_$signal]
  }
  disconnect_bd_net [get_bd_nets -of_objects [get_bd_pins flexray_can_telemetry_0/m_ready]] [get_bd_pins flexray_can_telemetry_0/m_ready]
  connect_bd_net [get_bd_pins can_telemetry_mux_0/a_ready] [get_bd_pins flexray_can_telemetry_0/m_ready]
  connect_bd_net [get_bd_pins can_telemetry_mux_0/b_ready] [get_bd_pins flexray_log_can_diagnostics_0/m_ready]
  connect_bd_net [get_bd_pins joystick_decoder_0/telemetry_ready] [get_bd_pins can_telemetry_mux_0/m_ready]
}
set_property CONFIG.ENABLED true [get_bd_cells flexray_log_can_diagnostics_0]
set_property CONFIG.CAN_ID 506 [get_bd_cells flexray_log_can_diagnostics_0]
if {[llength [get_bd_cells -quiet control_snapshot_0]] == 0} {
  create_bd_cell -type module -reference control_snapshot control_snapshot_0
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins control_snapshot_0/src_clk]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins control_snapshot_0/dst_clk]
  connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins control_snapshot_0/rst]
  foreach signal {torque sign enable} {
    disconnect_bd_net [get_bd_nets -of_objects [get_bd_pins flexray_torque_inter_0/$signal]] [get_bd_pins flexray_torque_inter_0/$signal]
    connect_bd_net [get_bd_pins joystick_decoder_0/$signal] [get_bd_pins control_snapshot_0/${signal}_in]
    connect_bd_net [get_bd_pins control_snapshot_0/${signal}_out] [get_bd_pins flexray_torque_inter_0/$signal]
  }
}
set_property CONFIG.ENABLED $enabled [get_bd_cells flexray_can_telemetry_0]
# The shared transmitter is needed for diagnostics even with frame telemetry off.
set_property CONFIG.ENABLE_CAN_TELEMETRY true [get_bd_cells joystick_decoder_0]
validate_bd_design
save_bd_design
if {$mode eq "prepare"} {
  # Save the reviewed source BD and module-reference descriptors, not outputs.
  set channel [open $active_bd r]; set contents [read $channel]; close $channel
  regsub {"gen_directory": "[^"]*"} $contents {"gen_directory": "../../../../flexray-interceptor-vivado.gen/sources_1/bd/bendbeam"} contents
  set channel [open [file join $sources bd bendbeam bendbeam.bd] w]; puts -nonewline $channel $contents; close $channel
  foreach descriptor [glob [file join [file dirname $active_bd] ip * *.xci]] {
    set name [file rootname [file tail $descriptor]]
    file mkdir [file join $sources bd bendbeam ip $name]
    set channel [open $descriptor r]; set contents [read $channel]; close $channel
    regsub {"gen_directory": "[^"]*"} $contents "\"gen_directory\": \"../../../../../../flexray-interceptor-vivado.gen/sources_1/bd/bendbeam/ip/$name\"" contents
    set contents [string map {local_verify.gen flexray-interceptor-vivado.gen} $contents]
    set channel [open [file join $sources bd bendbeam ip $name ${name}.xci] w]; puts -nonewline $channel $contents; close $channel
  }
  puts "PREPARE_PASS: frame telemetry disabled; diagnostic CAN 0x1FA enabled; source BD refreshed"
  exit
}
generate_target all [get_files bendbeam.bd]
generate_target all [get_ips fifo_generator_0]
add_files -norecurse [make_wrapper -files [get_files bendbeam.bd] -top]
add_files -fileset constrs_1 [file join $repo flexray-interceptor-vivado.srcs constrs_1 new bendbeam.xdc]
set_property top bendbeam_wrapper [current_fileset]
update_compile_order -fileset sources_1
synth_design -top bendbeam_wrapper -part xa7s50csga324-1Q -flatten_hierarchy rebuilt
set dadc_rams [get_cells -hierarchical -filter {NAME =~ *dadc_queue* && REF_NAME =~ RAM*}]
set bcm_rams [get_cells -hierarchical -filter {NAME =~ *bcm_queue* && REF_NAME =~ RAM*}]
if {[llength $dadc_rams] == 0 || [llength $bcm_rams] == 0} {
  error "Per-direction logging FIFOs did not infer RAM storage"
}
puts "LOG_FIFO_RAM_RESULT dadc=[llength $dadc_rams] bcm=[llength $bcm_rams] depth=32"
read_xdc [file join $repo flexray-interceptor-vivado.srcs constrs_1 new control_snapshot_cdc.xdc]
read_xdc [file join $repo flexray-interceptor-vivado.srcs constrs_1 new spi_cdc.xdc]
write_checkpoint -force [file join $build synthesized.dcp]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -max_paths 10 -report_unconstrained -file [file join $build timing_summary.rpt]
report_bus_skew -file [file join $build bus_skew.rpt]
set skew_file [open [file join $build bus_skew.rpt] r]
set skew_report [read $skew_file]; close $skew_file
if {[string first "VIOLATED" $skew_report] >= 0} { error "Bus skew constraints are not met" }
report_cdc -details -file [file join $build cdc.rpt]
report_methodology -file [file join $build methodology.rpt]
report_drc -file [file join $build drc.rpt]
report_utilization -file [file join $build utilization.rpt]
source [file join $repo scripts check_spi_paths.tcl]
write_checkpoint -force [file join $build routed.dcp]
check_spi_paths $build
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
set sync_count [llength [get_cells -hierarchical -filter {NAME =~ */control_snapshot_0/U0/request_meta_reg || NAME =~ */control_snapshot_0/U0/ack_meta_reg}]]
if {$sync_count != 2} { error "Control CDC synchronizer constraints did not match both toggle stages" }
puts "VERIFY_RESULT telemetry=$enabled diagnostics=true CAN_ID=0x1FA WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold]"
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
  error "Setup/hold timing constraints are not met; see timing_summary.rpt"
}
exit
} verification_error verification_opts]} {
  puts stderr "VERIFY_ERROR: $verification_error"
  puts stderr [dict get $verification_opts -errorinfo]
  exit 1
}
