# Timing of the HDMI transmitter's inputs (ADV7513), read after the IP constraint files so that the
# pixel PLL's clock exists (this file is listed last in baseline_a55.qsf).
#
# The pixel clock leaves on hdmi_tx_clk, not inverted. The ADV7513 samples data, DE and the syncs
# on the rising edge of that clock and needs them stable 1.8 ns before it and 1.3 ns after it
# (datasheet: tVSU, tVHLD). These constraints make the build check that at the FPGA's pins.
# They do not know the board: the clock pin is in a 1.1 V bank and the data pins are 3.3 V, so
# the board has some extra delay in the clock line that no report shows. A build with about
# 3.8 ns before the edge and 1.9 ns after it at the pins gave a clean image (2026-11-13).
set hdmi_pix_clock [get_clocks {u_baseline_top|hdmi_pll|altera_iopll_inst_outclk0}]
create_generated_clock -name hdmi_tx_clk_pin -source [get_clock_info -targets $hdmi_pix_clock] [get_ports {hdmi_tx_clk}]
set hdmi_video_pins [get_ports {hdmi_tx_d[*] hdmi_tx_de hdmi_tx_hs hdmi_tx_vs}]
set_output_delay -clock hdmi_tx_clk_pin -max  1.8 $hdmi_video_pins
set_output_delay -clock hdmi_tx_clk_pin -min -1.3 $hdmi_video_pins
