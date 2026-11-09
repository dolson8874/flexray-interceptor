# Inspect an already routed checkpoint without repeating placement/routing.
set repo [file normalize [file join [file dirname [info script]] ..]]
if {[catch {
  set build [file join $repo tests design_[lindex $argv 0].sim]
  open_checkpoint [file join $build routed.dcp]
  source [file join $repo scripts check_spi_paths.tcl]
  check_spi_paths $build
  set setup [get_timing_paths -delay_type max -max_paths 1]
  set hold [get_timing_paths -delay_type min -max_paths 1]
  puts "SPI_CHECKPOINT_RESULT WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold]"
  if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} { error "Internal timing not met" }
  exit
} message]} { puts stderr "SPI_CHECKPOINT_ERROR: $message";exit 1 }
