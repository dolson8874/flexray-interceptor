# The FT4232H MPSSE signals are asynchronous to the 80 MHz fabric clock.
# Exclude only each pin-to-first-synchronizer path. Keep the second stages and
# all SPI logic timed; external setup/hold requirements are a separate budget.
# Keep XDC declarative: flow checks/loops live in scripts/check_spi_paths.tcl.
set_false_path -from [get_ports BDBUS0] -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ */SPI_SLAVE_0/U0/sclk_meta_reg}] -filter {REF_PIN_NAME == D}]
set_false_path -from [get_ports BDBUS3] -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ */SPI_SLAVE_0/U0/cs_n_meta_reg}] -filter {REF_PIN_NAME == D}]
set_false_path -from [get_ports BDBUS1] -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ */SPI_SLAVE_0/U0/mosi_meta_reg}] -filter {REF_PIN_NAME == D}]
