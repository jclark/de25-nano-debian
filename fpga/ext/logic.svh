// Hook: the declarations and logic of a derived design, included in the top-level module just
// before the system (baseline_top) is instantiated. A derived design replaces this file with
// its own, which must drive the three signals below.
//
// The file is read with `default_nettype none`: declare every wire, here, including those the
// derived design's ext/connections.svh uses. It may use the top level's ports and these signals:
//     sys_clk_100, sys_clk_100_reset_n   the 100 MHz system clock and its reset
//     jp1_14_ptp_trig                    the PPS input, which also goes to EMAC0
//     jp1_6_ptp_pps                      EMAC0's PPS output

// The 32 FPGA-to-SoC interrupt lines (GIC SPI 49 + bit, level): none used.
assign fpga2hps_interrupts = '0;

// The timestamp hubs' counter input: a running clock and a count of zero.
assign hub_cnt_clk = sys_clk_100;
assign hub_cnt     = 64'd0;
