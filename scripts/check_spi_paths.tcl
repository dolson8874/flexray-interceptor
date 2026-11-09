# Post-route checks. MOSI data is unused in the logging-only BD and its pair
# may be removed by opt_design; SCLK/CS must retain both synchronizer stages.
proc check_spi_paths {build} {
  set total 0
  foreach signal {sclk cs_n mosi} {
    set first [get_cells -quiet -hierarchical -filter "NAME =~ */SPI_SLAVE_0/U0/${signal}_meta_reg"]
    set second [get_cells -quiet -hierarchical -filter "NAME =~ */SPI_SLAVE_0/U0/${signal}_reg_reg || NAME =~ */SPI_SLAVE_0/U0/${signal}_reg"]
    if {$signal eq "mosi" && [llength $first] == 0 && [llength $second] == 0} { continue }
    if {[llength $first] != 1 || [llength $second] != 1} { error "SPI $signal synchronizer pair is incomplete: first=$first second=$second" }
    foreach stage [concat $first $second] {
      if {![get_property ASYNC_REG $stage]} { error "SPI stage $stage lost ASYNC_REG" }
    }
    incr total 2
    if {[llength [get_timing_paths -from $first -to $second -max_paths 1]] == 0} {
      error "SPI $signal second synchronizer stage is not timed"
    }
    report_timing -from $first -to $second -max_paths 1 -file [file join $build spi_${signal}_sync_timing.rpt]
  }
  set miso [get_cells -quiet -hierarchical -filter {NAME =~ */SPI_SLAVE_0/U0/MISO_reg}]
  if {[llength $miso] != 1} { error "SPI MISO register is missing" }
  # Explicit endpoints permit inspection, not an external setup/hold signoff.
  report_timing -from [get_pins -of_objects $miso -filter {REF_PIN_NAME == C}] -to [get_ports BDBUS2] -max_paths 1 -file [file join $build spi_miso_timing.rpt]
  report_exceptions -coverage -file [file join $build spi_exception_coverage.rpt]
  puts "SPI_CDC_RESULT stages=$total MISO_LOC=[get_property LOC $miso] external_timing=NOT_VALIDATED"
}
