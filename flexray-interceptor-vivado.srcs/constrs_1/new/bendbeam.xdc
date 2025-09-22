
set_property PACKAGE_PIN M17 [get_ports BDBUS1]
set_property PACKAGE_PIN G16 [get_ports RELAY_DRV]
set_property PACKAGE_PIN J6 [get_ports RstBtn]
set_property PACKAGE_PIN M3 [get_ports O_CAN1_TX]
set_property PACKAGE_PIN K1 [get_ports FR_RX_1]
set_property PACKAGE_PIN K2 [get_ports FR_TX_1]
set_property PACKAGE_PIN N18 [get_ports BDBUS3]
set_property PACKAGE_PIN L1 [get_ports FR_TXEN_1]
set_property PACKAGE_PIN M16 [get_ports BDBUS0]
set_property PACKAGE_PIN M2 [get_ports O_CAN1_RX]
set_property PACKAGE_PIN L4 [get_ports FR_RX_0]
set_property PACKAGE_PIN K3 [get_ports FR_TXEN_0]
set_property PACKAGE_PIN K4 [get_ports FR_TX_0]

set_property PACKAGE_PIN R2 [get_ports CLK12M]
set_property IOSTANDARD LVCMOS33 [get_ports BDBUS1]
set_property IOSTANDARD LVCMOS33 [get_ports CLK12M]
set_property IOSTANDARD LVCMOS33 [get_ports BDBUS0]
set_property IOSTANDARD LVCMOS33 [get_ports BDBUS3]
set_property IOSTANDARD LVCMOS33 [get_ports FR_RX_0]
set_property IOSTANDARD LVCMOS33 [get_ports FR_RX_1]
set_property IOSTANDARD LVCMOS33 [get_ports FR_TX_0]
set_property IOSTANDARD LVCMOS33 [get_ports FR_TX_1]
set_property IOSTANDARD LVCMOS33 [get_ports FR_TXEN_0]
set_property IOSTANDARD LVCMOS33 [get_ports FR_TXEN_1]
set_property IOSTANDARD LVCMOS33 [get_ports O_CAN1_RX]
set_property IOSTANDARD LVCMOS33 [get_ports O_CAN1_TX]
set_property IOSTANDARD LVCMOS33 [get_ports RELAY_DRV]
set_property IOSTANDARD LVCMOS33 [get_ports RstBtn]

set_property DRIVE 8 [get_ports FR_TX_0]
set_property DRIVE 8 [get_ports FR_TX_1]
set_property DRIVE 8 [get_ports FR_TXEN_0]
set_property DRIVE 8 [get_ports FR_TXEN_1]
set_property DRIVE 8 [get_ports O_CAN1_TX]
set_property DRIVE 8 [get_ports RELAY_DRV]

set_property PACKAGE_PIN M1 [get_ports CAN_STBY]

set_property IOSTANDARD LVCMOS33 [get_ports CAN_STBY]
set_property DRIVE 8 [get_ports CAN_STBY]

## Quad SPI Flash
#set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

set_property PACKAGE_PIN R15 [get_ports LED4]
set_property IOSTANDARD LVCMOS33 [get_ports LED4]
set_property DRIVE 8 [get_ports LED4]

set_property IOSTANDARD LVCMOS33 [get_ports BDBUS2]
set_property DRIVE 8 [get_ports BDBUS2]

#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets RstBtn_IBUF]
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical *RstBtn_IBUF]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical RstBtn_IBUF]

set_property PACKAGE_PIN V17 [get_ports LED5]
set_property IOSTANDARD LVCMOS33 [get_ports LED5]

set_property DRIVE 8 [get_ports LED5]

set_false_path -from [get_clocks -of_objects [get_pins bendbeam_i/clk_wiz_0/inst/mmcm_adv_inst/CLKOUT2]] -to [get_clocks -of_objects [get_pins bendbeam_i/clk_wiz_0/inst/mmcm_adv_inst/CLKOUT0]]


set_property PACKAGE_PIN T15 [get_ports LED3]
set_property IOSTANDARD LVCMOS33 [get_ports LED3]
set_property DRIVE 8 [get_ports LED3]
set_property SLEW SLOW [get_ports LED3]

set_property PACKAGE_PIN M18 [get_ports BDBUS2]
set_property SLEW SLOW [get_ports LED4]
set_property SLEW SLOW [get_ports BDBUS2]
set_property SLEW SLOW [get_ports CAN_STBY]
set_property SLEW SLOW [get_ports FR_TX_0]
set_property SLEW SLOW [get_ports FR_TX_1]
set_property SLEW SLOW [get_ports FR_TXEN_0]
set_property SLEW SLOW [get_ports FR_TXEN_1]
set_property SLEW SLOW [get_ports O_CAN1_TX]

set_property PACKAGE_PIN U15 [get_ports LED2]
set_property IOSTANDARD LVCMOS33 [get_ports LED2]
set_property DRIVE 8 [get_ports LED2]

set_property PACKAGE_PIN V16 [get_ports LED1]
set_property IOSTANDARD LVCMOS33 [get_ports LED1]
set_property DRIVE 8 [get_ports LED1]
set_property SLEW SLOW [get_ports LED1]
