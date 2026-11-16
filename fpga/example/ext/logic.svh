// Example of a design built on the base (fpga/README.md, "Building on this design"): a
// square wave of 1 Hz on JP1 pin 31. This file takes the place of the base's ext/logic.svh,
// so it also drives the three signals that file drives.

// The 32 FPGA-to-SoC interrupt lines: none used.
assign fpga2hps_interrupts = '0;

// The timestamp hubs' counter input: a running clock and a count of zero.
assign hub_cnt_clk = sys_clk_100;
assign hub_cnt     = 64'd0;

// Half a second of the 100 MHz system clock is 50,000,000 counts.
reg [25:0] blink_count;
reg        blink;
always_ff @(posedge sys_clk_100) begin
    if (!sys_clk_100_reset_n) begin
        blink_count <= '0;
        blink       <= 1'b0;
    end else if (blink_count == 26'd49_999_999) begin
        blink_count <= '0;
        blink       <= ~blink;
    end else begin
        blink_count <= blink_count + 26'd1;
    end
end
assign jp1_31_blink = blink;
