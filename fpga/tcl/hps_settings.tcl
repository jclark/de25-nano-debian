# Print the SoC component's settings, one "HPS name=value" line each, sorted. apply.sh keeps
# these lines and compares them with fpga/hps-settings.txt.
# Run: qsys-script --quartus-project=top.qpf --system-file=hps_subsys.qsys --script=hps_settings.tcl
package require qsys
load_component u_agilex_hps
foreach p [lsort [get_component_parameters]] {
    puts "HPS $p=[get_component_parameter_value $p]"
}
