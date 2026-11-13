# Platform Designer part of the HDMI video path, added to baseline_top.qsys:
#  - a 148.5 MHz pixel clock PLL fed from the board's 50 MHz CLOCK2_50 (1920x1080 at 60 Hz);
#  - an address span extender in front of the SoC's FPGA-to-SDRAM port (40-bit address, 256-bit
#    data), exported to the top level, where src/hdmi_scanout.sv reads the frame buffer through it.
# Altera's self-test master is disconnected from that port: it takes one master.
# Run: qsys-script --quartus-project=top.qpf --system-file=baseline_top.qsys --script=hdmi_base.tcl
package require qsys
proc setp {k v} { if {[catch {set_component_parameter_value $k $v} e]} { puts "SKIP $k: $e" } }
proc mk {inst type} { add_component $inst ip/baseline_top/$inst.ip $type; load_component $inst }
proc done {inst} { save_component; reload_component_footprint $inst }

mk hdmi_refclk altera_clock_bridge
setp EXPLICIT_CLOCK_RATE 50000000
setp NUM_CLOCK_OUTPUTS 1
done hdmi_refclk

mk hdmi_pll altera_iopll
setp gui_reference_clock_frequency 50.0
setp gui_operation_mode direct
setp gui_use_locked true
setp gui_number_of_clocks 1
setp gui_output_clock_frequency0 148.5
done hdmi_pll

mk hdmi_span altera_address_span_extender
setp DATA_WIDTH 256
setp BYTEENABLE_WIDTH 32
setp MASTER_ADDRESS_WIDTH 40
setp SLAVE_ADDRESS_WIDTH 27
setp BURSTCOUNT_WIDTH 5
setp SUB_WINDOW_COUNT 1
setp MASTER_ADDRESS_DEF 0
setp ENABLE_SLAVE_PORT false
setp MAX_PENDING_READS 64
done hdmi_span

remove_connection u_fabric_subsys.f2sdram_bridge_adapter/u_shell_subsys.f2sdram
add_connection hdmi_refclk.out_clk hdmi_pll.refclk
add_connection u_shell_subsys.system_reset_n hdmi_pll.reset
add_connection u_shell_subsys.system_clock hdmi_span.clock
add_connection u_shell_subsys.system_reset_n hdmi_span.reset
add_connection hdmi_span.expanded_master u_shell_subsys.f2sdram
set_connection_parameter_value hdmi_span.expanded_master/u_shell_subsys.f2sdram baseAddress 0x0

add_interface hdmi_clk50 clock sink
set_interface_property hdmi_clk50 EXPORT_OF hdmi_refclk.in_clk
add_interface hdmi_pix_clk clock source
set_interface_property hdmi_pix_clk EXPORT_OF hdmi_pll.outclk0
add_interface hdmi_pll_locked conduit end
set_interface_property hdmi_pll_locked EXPORT_OF hdmi_pll.locked
add_interface hdmi_mem avalon slave
set_interface_property hdmi_mem EXPORT_OF hdmi_span.windowed_slave
save_system
puts SAVED
