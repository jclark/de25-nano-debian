project_open top -revision baseline_a55
create_timing_netlist
read_sdc
update_timing_netlist
foreach corner {setup hold} {
  report_timing -false_path -$corner -to [get_registers {*u_hdmi_scanout|vid_d[*]}] -npaths 400 -detail summary -file fp_$corner.rpt
}
project_close
