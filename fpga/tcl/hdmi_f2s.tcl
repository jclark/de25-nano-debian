# The HPS FPGA-to-SDRAM firewall only accepts transactions with AxUSER[7:0] = 0xE0 (HPS TRM
# 814346, 13.4.2.4.3). Altera's f2sdram_adapter (custom_ip/) sets it. hdmi_base.tcl connected the
# scan-out's span extender straight to the port, so its reads carried no marker and were
# refused: the display showed noise. This puts an adapter between the span extender and the port.
# Run: qsys-script --quartus-project=top.qpf --system-file=baseline_top.qsys --script=hdmi_f2s.tcl \
#        --search-path="custom_ip/**/*,$"
package require qsys
add_component hdmi_f2s ip/baseline_top/hdmi_f2s.ip f2sdram_adapter
load_component hdmi_f2s
set_component_parameter_value DATA_WIDTH 256
set_component_parameter_value ADDRESS_WIDTH 40
save_component
reload_component_footprint hdmi_f2s

remove_connection hdmi_span.expanded_master/u_shell_subsys.f2sdram
add_connection u_shell_subsys.system_clock hdmi_f2s.clock
add_connection u_shell_subsys.system_reset_n hdmi_f2s.reset
add_connection hdmi_span.expanded_master hdmi_f2s.axi4_sub
set_connection_parameter_value hdmi_span.expanded_master/hdmi_f2s.axi4_sub baseAddress 0x0
add_connection hdmi_f2s.axi4_man u_shell_subsys.f2sdram
set_connection_parameter_value hdmi_f2s.axi4_man/u_shell_subsys.f2sdram baseAddress 0x0
save_system
puts SAVED
