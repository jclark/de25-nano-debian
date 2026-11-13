# Pass the added SoC-to-FPGA connections up one level of the design.
# Usage: qsys-script --quartus-project=top.qpf --system-file=<level>.qsys \
#          --script=export_connections.tcl <instance>
# Run for hps_subsys.qsys (u_agilex_hps), shell_subsys.qsys (its hps_subsys instance) and
# baseline_top.qsys (u_shell_subsys), in that order.
package require qsys
set inst [lindex $argv 0]
reload_component_footprint $inst
set have [get_instance_interfaces $inst]
foreach {name type dir} {
    emac0_ptp       conduit end
    uart0           conduit end
    I2C0            conduit end
    I2C0_scl_i      clock   sink
    I2C0_scl_oe     clock   source
    emac0_i2c       conduit end
    spim0           conduit end
    spim0_sclk_out  clock   source
} {
    if {[lsearch -exact $have $name] < 0} { puts "MISSING $name on $inst"; continue }
    add_interface $name $type $dir
    set_interface_property $name EXPORT_OF $inst.$name
    puts "EXPORTED $name"
}
save_system
