project_open top -revision baseline_a55
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -to_clock hdmi_tx_clk_pin -setup -npaths 1 -detail full_path -file io_setup.rpt
report_timing -to_clock hdmi_tx_clk_pin -hold  -npaths 1 -detail full_path -file io_hold.rpt
foreach c [get_available_operating_conditions] {
  set_operating_conditions $c
  update_timing_netlist
  report_timing -to_clock hdmi_tx_clk_pin -setup -npaths 1 -detail summary -file io_setup_$c.rpt
  report_timing -to_clock hdmi_tx_clk_pin -hold  -npaths 1 -detail summary -file io_hold_$c.rpt
}
project_close
