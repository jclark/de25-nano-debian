# SoC-to-FPGA connections added to Altera's design (the set fixed by the first-stage image):
#   EMAC0 PTP signals, UART0, I2C0 (HDMI and fan chip bus), I2C_EMAC0 (spare, header), SPI master 0.
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
save_component
reload_component_footprint u_agilex_hps
foreach i [get_instance_interfaces u_agilex_hps] { puts "IF $i" }
