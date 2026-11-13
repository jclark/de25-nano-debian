project_open top -revision baseline_a55
create_timing_netlist
read_sdc
update_timing_netlist
report_datasheet -file hdmi_datasheet.rpt
foreach p {hdmi_tx_clk hdmi_tx_de hdmi_tx_hs hdmi_tx_vs hdmi_tx_d[0] hdmi_tx_d[7] hdmi_tx_d[12] hdmi_tx_d[23]} {
  catch {report_path -to [get_ports $p] -npaths 1 -panel_name p -file hdmi_path_[string map {[ _ ] _} $p].rpt -show_routing 0} e
}
project_close
