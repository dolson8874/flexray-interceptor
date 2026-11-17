# Local file generation only; never opens a hardware target.
# argv: routed checkpoint, output directory, explicit release basename.
if {[catch {
  if {[llength $argv] != 3} { error "Expected routed checkpoint, output directory and release basename" }
  set checkpoint [file normalize [lindex $argv 0]]
  set output [file normalize [lindex $argv 1]]
  set release_name [lindex $argv 2]
  if {![regexp {^bendbeam_fw_[0-9]+\.[0-9]+\.[0-9]+_build[0-9]+$} $release_name]} {
    error "Invalid release basename; expected bendbeam_fw_X.Y.Z_buildN"
  }
  file mkdir $output
  set_param general.maxThreads 4
  open_checkpoint $checkpoint
  set setup [get_timing_paths -delay_type max -max_paths 1]
  set hold [get_timing_paths -delay_type min -max_paths 1]
  if {![llength $setup] || ![llength $hold]} { error "Missing timing paths" }
  if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "Setup/hold timing not met"
  }
  set base [file join $output $release_name]
  report_drc -file [file join $output pre_bitstream_drc.rpt]
  if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} {
    error "DRC errors prevent bitstream generation"
  }
  write_bitstream -force ${base}.bit
  # MT25QL128: 128 Mbit (16 MiB), SPI x4, boot image at address zero.
  write_cfgmem -force -format bin -interface SPIx4 -size 16 \
    -loadbit "up 0x00000000 ${base}.bit" -file ${base}.bin
  write_cfgmem -force -format mcs -interface SPIx4 -size 16 \
    -loadbit "up 0x00000000 ${base}.bit" -file ${base}.mcs
  puts "PROGRAMMING_FILES_PASS WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold] output=$output"
  exit
} build_error build_options]} {
  puts stderr "PROGRAMMING_FILES_ERROR: $build_error"
  puts stderr [dict get $build_options -errorinfo]
  exit 1
}
