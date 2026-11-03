# Apply to synthesized control_snapshot_0 during implementation. Only first
# toggle synchronizer stages are asynchronous. Hold bundled data stable until
# acknowledgement and bound its route/skew to one 80 MHz clock period.
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ */control_snapshot_0/U0/request_meta_reg || NAME =~ */control_snapshot_0/U0/ack_meta_reg}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 12.5 -from [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/held_data_reg*}] -to [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/delivered_data_reg*}]
set_bus_skew 12.5 -from [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/held_data_reg*}] -to [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ */control_snapshot_0/U0/delivered_data_reg*}]
