# SoC-to-FPGA connections added to Altera's design. These are the SoC settings that the HPS
# image (phase 1, in the flash) fixes: a core image loads only on an HPS image with the same
# settings. They are the settings of the boot package named in fpga/BOOT_NAME, and
# fpga/hps-settings.txt records them; apply.sh fails when they no longer agree.
#   EMAC0 PTP signals; UART0; I2C0 (the bus of the HDMI transmitter and the fan controller);
#   I2C_EMAC0 and SPI master 0 (header JP1); I2C_EMAC1 and SPI master 1 (header JP2);
#   EMAC1, with nothing attached: routing it to the FPGA is what makes the SoC offer the
#   timestamp hubs' counter input from the FPGA (emac_timestamp_clk, emac_timestamp_data).
#   The base core ties both off; a derived design may drive the counter input.
# Run: qsys-script --quartus-project=top.qpf --system-file=hps_subsys.qsys --script=hps_connections.tcl
package require qsys
load_component u_agilex_hps
set_component_parameter_value EMAC0_PTP true
set_component_parameter_value UART0_PinMuxing FPGA
set_component_parameter_value UART0_Mode No_flow_control
set_component_parameter_value I2C0_PinMuxing FPGA
set_component_parameter_value I2C0_Mode default
set_component_parameter_value I2CEMAC0_PinMuxing FPGA
set_component_parameter_value I2CEMAC0_Mode default
set_component_parameter_value SPIM0_PinMuxing FPGA
set_component_parameter_value SPIM0_Mode Single_slave_selects
set_component_parameter_value I2CEMAC1_PinMuxing FPGA
set_component_parameter_value I2CEMAC1_Mode default
set_component_parameter_value SPIM1_PinMuxing FPGA
set_component_parameter_value SPIM1_Mode Single_slave_selects
set_component_parameter_value EMAC1_PinMuxing FPGA
set_component_parameter_value EMAC1_Mode RGMII_with_MDIO
# Routing an EMAC to the FPGA turns on the PTP reference clock input from the FPGA, which is
# one selection for all the EMACs. Keep the internal PTP clock: EMAC0's PHC stays as it was.
set_component_parameter_value FPGA_EMAC_PTP_clk_en false
save_component
reload_component_footprint u_agilex_hps
foreach i [get_instance_interfaces u_agilex_hps] { puts "IF $i" }
