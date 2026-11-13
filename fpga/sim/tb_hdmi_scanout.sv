// Test bench for src/hdmi_scanout.sv.
//
// What it does:
//  - clocks the block at 148.5 MHz (pixel side) and 100 MHz (memory side);
//  - stands in for the memory: answers the block's Avalon read bursts with words in which every
//    pixel carries its own number (pixel n of the frame has the value n in its low 24 bits), with
//    optional random waits and gaps (+stress=1);
//  - measures the raster on the outputs as a receiver would, sampling on the rising clock edge,
//    and checks it against CEA-861 format 16 (1920x1080 progressive, 60 Hz);
//  - checks that the pixel shown at screen position (x, y) is pixel number y*1920 + x;
//  - runs Terasic's timing generator (vga_generator.v, known to work on this board) on the same
//    clock with the 1080p60 parameters of Terasic's vpg.v, and compares DE, HSYNC and VSYNC with
//    this block's clock by clock over one frame, both lined up on the leading edge of VSYNC.
//
// Run: sim/run.sh   (Icarus Verilog in the de25-sim container)
`timescale 1ps/1ps
module tb;
    localparam int HT = 2200, VT = 1125, HA = 1920, VA = 1080;
    localparam int HFP = 88, HSW = 44, HBP = 148, VFP = 4, VSW = 5, VBP = 36;
    localparam int FRAME = HT * VT;
    localparam logic [26:0] FB_WORD0 = 27'h5F8_0000;      // 0xBF000000 / 32
    localparam int FRAME_WORDS = HA * VA / 8;

    parameter int FIFO_AW = 12;           // override: iverilog -Ptb.FIFO_AW=7
    int stress = 0, frames = 4, seed = 1, stall = 0, bstall = 0;
    initial begin
        void'($value$plusargs("stress=%d", stress));
        void'($value$plusargs("frames=%d", frames));
        void'($value$plusargs("seed=%d", seed));
        void'($value$plusargs("stall=%d", stall));
        void'($value$plusargs("bstall=%d", bstall));   // +bstall=N: the memory goes silent for N us about 60 times a frame
        $display("config: stress=%0d frames=%0d seed=%0d stall=%0d", stress, frames, seed, stall);
    end

    // ---------------------------------------------------------------- clocks and resets
    logic pix_clk = 0, mem_clk = 0, mem_reset_n = 0, pll_locked = 0;
    always #3367 pix_clk = ~pix_clk;        // 148.5 MHz (6.734 ns)
    always #5000 mem_clk = ~mem_clk;        // 100 MHz
    initial begin
        #123456 pll_locked = 1;
        #234567 mem_reset_n = 1;
    end
    // +relock=1: the pixel PLL loses lock for 2 us in the middle of the 2nd frame;
    // +memreset=1: the memory side is reset for 2 us in the middle of the 2nd frame.
    // Raster or pixel errors are expected in the disturbed frame; the frames after must be clean.
    int relock = 0, memreset = 0;
    initial begin
        void'($value$plusargs("relock=%d", relock));
        void'($value$plusargs("memreset=%d", memreset));
        #(64'd25_000_000_000);
        if (relock)   begin $display("disturbance: pixel PLL unlocked for 2 us");  pll_locked = 0;  #2_000_000 pll_locked = 1;  end
        if (memreset) begin $display("disturbance: memory side reset for 2 us");   mem_reset_n = 0; #2_000_000 mem_reset_n = 1; end
    end

    // ---------------------------------------------------------------- the block under test
    wire  [26:0]  mem_address;
    wire  [4:0]   mem_burstcount;
    wire          mem_read;
    logic [255:0] mem_readdata = '0;
    logic         mem_readdatavalid = 0, mem_waitrequest = 0;
    wire  [23:0]  vid_d;
    wire          vid_de, vid_hs, vid_vs, dbg_bad;

    hdmi_scanout #(.AW(FIFO_AW)) dut (
        .mem_clk(mem_clk), .mem_reset_n(mem_reset_n),
        .mem_address(mem_address), .mem_burstcount(mem_burstcount), .mem_read(mem_read),
        .mem_readdata(mem_readdata), .mem_readdatavalid(mem_readdatavalid),
        .mem_waitrequest(mem_waitrequest),
        .pix_clk(pix_clk), .pix_pll_locked(pll_locked),
        .vid_d(vid_d), .vid_de(vid_de), .vid_hs(vid_hs), .vid_vs(vid_vs), .dbg_bad(dbg_bad)
    );

    // ---------------------------------------------------------------- memory model (Avalon slave)
    // Accepted bursts wait in a ring; words come back in order, one per clock at most.
    logic [26:0] q_addr [0:255];
    logic [7:0]  q_head = 0, q_tail = 0;
    int          q_word = 0;             // next word of the burst at the head
    int          lat = 0;                // clocks before the head burst may start answering
    longint      bursts = 0, words = 0;
    int          mem_errors = 0;
    logic [26:0] expect_addr = FB_WORD0;
    int          frame_words_req = 0;
    longint      waited = 0;              // clocks a request was held off by waitrequest
    int          frame_starts = 0;        // bursts seen at the first word of the frame
    int          stall_cnt = 0;           // +stall=N: in the 2nd frame the memory stops answering for
                                          // N microseconds when the last burst of the frame is requested

    function automatic logic [255:0] word_at(input logic [26:0] a);
        logic [255:0] w;
        logic [31:0]  n;
        for (int i = 0; i < 8; i++) begin
            n = (32'(a) - 32'(FB_WORD0)) * 8 + i;
            w[32*i +: 32] = {8'hA5, n[23:0]};
        end
        return w;
    endfunction

    always @(posedge mem_clk) begin
        // request side
        if (mem_read && !mem_waitrequest) begin
            bursts <= bursts + 1;
            if (mem_burstcount != 5'd16) begin
                mem_errors++; if (mem_errors < 10) $display("MEM ERROR: burstcount %0d", mem_burstcount);
            end
            if (mem_address < FB_WORD0 || mem_address + 16 > FB_WORD0 + FRAME_WORDS) begin
                mem_errors++; if (mem_errors < 10) $display("MEM ERROR: burst at word %h is outside the frame", mem_address);
            end
            if (stall != 0 && frame_starts == 2 && mem_address == FB_WORD0 + FRAME_WORDS - 16 && stall_cnt == 0) begin
                stall_cnt = stall * 100;                   // 100 memory clocks a microsecond
                $display("memory model: stalling for %0d us at the last burst of frame %0d", stall, frame_starts);
            end
            if (bstall != 0 && stall_cnt == 0 && ($urandom(seed) % 270) == 0) stall_cnt = bstall * 100;
            if (mem_address == FB_WORD0) begin
                frame_starts++;
                if (frame_words_req != 0 && frame_words_req != FRAME_WORDS) begin
                    mem_errors++; if (mem_errors < 10) $display("MEM ERROR: previous frame requested %0d words, not %0d", frame_words_req, FRAME_WORDS);
                end
                frame_words_req = 16;
            end else begin
                if (mem_address != expect_addr) begin
                    mem_errors++; if (mem_errors < 10) $display("MEM ERROR: burst at word %h, expected %h", mem_address, expect_addr);
                end
                frame_words_req += 16;
            end
            expect_addr = mem_address + 27'd16;
            q_addr[q_tail] = mem_address;
            q_tail = q_tail + 8'd1;
            if (q_tail == q_head) begin mem_errors++; $display("MEM ERROR: more than 255 bursts outstanding"); end
        end
        mem_waitrequest <= stress ? (($urandom(seed) % 4) == 0) : 1'b0;
        if (mem_read && mem_waitrequest) waited <= waited + 1;

        // response side
        mem_readdatavalid <= 1'b0;
        if (stall_cnt > 0) stall_cnt--;
        else if (q_head != q_tail) begin
            if (lat > 0) lat--;
            else if (!stress || ($urandom(seed) % 5) != 0) begin
                mem_readdata      <= word_at(q_addr[q_head] + 27'(q_word));
                mem_readdatavalid <= 1'b1;
                words <= words + 1;
                if (q_word == 15) begin
                    q_word = 0; q_head = q_head + 8'd1;
                    lat = stress ? ($urandom(seed) % 12) : 2;
                end else q_word++;
            end
        end
    end

    // ---------------------------------------------------------------- raster and pixel checker
    longint t = 0;                         // pixel clock number
    logic   de_q = 0, hs_q = 0, vs_q = 0;
    longint hs_rise_t = -1, hs_fall_t = -1, de_rise_t = -1, de_fall_t = -1, vs_rise_t = -1, vs_fall_t = -1;
    int     frame_no = 0, line_no = -1, x = 0;
    int     hs_in_frame = 0, de_lines = 0;
    int     ras_errors = 0, pix_errors = 0, black_px = 0, good_px = 0, blank_nonzero = 0;
    longint wrong_total = 0, black_total = 0, blank_total = 0;
    logic   first_de_of_frame = 0;
    int     ln;
    logic [23:0] want;

    task automatic ras(input string what, input longint got, input longint want);
        if (got != want) begin
            ras_errors++;
            if (ras_errors <= 20) $display("RASTER ERROR frame %0d line %0d: %s = %0d, CEA-861 says %0d", frame_no, line_no, what, got, want);
        end
    endtask

    always @(posedge pix_clk) begin
        t <= t + 1;
        de_q <= vid_de; hs_q <= vid_hs; vs_q <= vid_vs;

        // --- horizontal
        if (vid_hs && !hs_q) begin
            if (hs_rise_t >= 0) ras("clocks from hsync to hsync", t - hs_rise_t, HT);
            if (de_fall_t >= 0 && de_fall_t > hs_rise_t) ras("clocks from end of DE to hsync (front porch)", t - de_fall_t, HFP);
            hs_rise_t <= t; hs_in_frame <= hs_in_frame + 1;
        end
        if (!vid_hs && hs_q) begin
            ras("hsync width", t - hs_rise_t, HSW);
            hs_fall_t <= t;
        end
        if (vid_de && !de_q) begin
            if (hs_rise_t >= 0) ras("clocks from hsync start to DE (sync + back porch)", t - hs_rise_t, HSW + HBP);
            de_rise_t <= t; de_lines <= de_lines + 1; line_no <= line_no + 1; x = 0;
            if (first_de_of_frame) begin
                ras("clocks from vsync start to first DE", t - vs_rise_t, (VSW + VBP) * HT + HSW + HBP);
                first_de_of_frame <= 0;
            end
        end
        if (!vid_de && de_q) begin
            ras("DE width", t - de_rise_t, HA);
            de_fall_t <= t;
        end

        // --- vertical
        if (vid_vs && !vs_q) begin
            if (!(vid_hs && !hs_q)) begin
                ras_errors++;
                $display("RASTER ERROR frame %0d: vsync rises %0d clocks after the last hsync rise; CEA-861 has them together", frame_no, t - hs_rise_t);
            end
            if (vs_rise_t >= 0) begin
                ras("clocks per frame", t - vs_rise_t, FRAME);
                ras("lines per frame (hsync pulses between vsyncs)", hs_in_frame + ((vid_hs && !hs_q) ? 0 : 0), VT);
                ras("lines with DE in the frame", de_lines, VA);
                $display("frame %0d done: %0d pixels right, %0d wrong, %0d black (ran out of data), %0d non-zero outside DE",
                         frame_no, good_px, pix_errors, black_px, blank_nonzero);
                wrong_total += pix_errors; black_total += black_px; blank_total += blank_nonzero;
            end
            if (de_fall_t >= 0) ras("clocks from last DE to vsync (4 lines + front porch)", t - de_fall_t, VFP * HT + HFP);
            vs_rise_t <= t; frame_no <= frame_no + 1; line_no <= -1;
            hs_in_frame <= (vid_hs && !hs_q) ? 1 : 0; de_lines <= 0; first_de_of_frame <= 1;
            good_px = 0; pix_errors = 0; black_px = 0; blank_nonzero = 0;
        end
        if (!vid_vs && vs_q) begin
            ras("vsync width in clocks (5 lines)", t - vs_rise_t, VSW * HT);
            if (!(vid_hs && !hs_q)) begin
                ras_errors++;
                $display("RASTER ERROR frame %0d: vsync falls %0d clocks after the last hsync rise; CEA-861 has them together", frame_no, t - hs_rise_t);
            end
            vs_fall_t <= t;
        end

        // --- pixel data (only once a first vsync has been seen, so line numbers are known)
        if (vs_rise_t >= 0) begin
            if (vid_de) begin
                ln = (vid_de && !de_q) ? line_no + 1 : line_no;
                want = 24'(ln * HA + x);
                if (vid_d === want) good_px++;
                else if (vid_d === 24'h0) black_px++;
                else begin
                    pix_errors++;
                    if (pix_errors <= 8) $display("PIXEL ERROR frame %0d line %0d x %0d: got %06h, expected %06h", frame_no, ln, x, vid_d, want);
                end
                x++;
            end else if (vid_d !== 24'h0) blank_nonzero++;
        end
    end

    // ---------------------------------------------------------------- Terasic's generator, same clock
    // Only with -DTERASIC (sim/run.sh sets it when TERASIC_HDMI names Terasic's sources).
    wire t_hs, t_vs, t_de;
`ifdef TERASIC
    vga_generator terasic (
        .clk(pix_clk), .reset_n(pll_locked),
        .h_total(12'd2199), .h_sync(12'd43), .h_start(12'd189), .h_end(12'd2109),
        .v_total(12'd1124), .v_sync(12'd4),  .v_start(12'd40),  .v_end(12'd1120),
        .v_active_14(12'd310), .v_active_24(12'd580), .v_active_34(12'd850),
        .vga_hs(t_hs), .vga_vs(t_vs), .vga_de(t_de), .vga_r(), .vga_g(), .vga_b()
    );
`else
    assign t_hs = 1'b1;
    assign t_vs = 1'b1;
    assign t_de = 1'b0;
`endif

    // Record one frame of each, starting at the clock of its own vsync leading edge.
    // Terasic's syncs are active low (the line rests high and pulses low), this block's active high.
    logic [2:0] ours [0:FRAME-1];
    logic [2:0] theirs [0:FRAME-1];
    int   o_n = -1, t_n = -1, o_vs_seen = 0, t_vs_seen = 0;
    logic t_vs_q = 1, o_vs_q2 = 0;
    always @(posedge pix_clk) begin
        o_vs_q2 <= vid_vs; t_vs_q <= t_vs;
        // this block: record from the 3rd vsync leading edge (a frame with data)
        if (vid_vs && !o_vs_q2) begin o_vs_seen++; if (o_vs_seen == 3) o_n = 0; end
        if (o_n >= 0 && o_n < FRAME) begin ours[o_n] = {vid_de, vid_hs, vid_vs}; o_n++; end
        // theirs: leading edge is the falling edge
        if (!t_vs && t_vs_q) begin t_vs_seen++; if (t_vs_seen == 2) t_n = 0; end
        if (t_n >= 0 && t_n < FRAME) begin theirs[t_n] = {t_de, ~t_hs, ~t_vs}; t_n++; end
    end

    task automatic compare_with_terasic;
        int dde = 0, dhs = 0, dvs = 0, shown = 0;
        int o_hs_first = -1, t_hs_first = -1, o_de_first = -1, t_de_first = -1, o_vs_len = 0, t_vs_len = 0, o_de = 0, t_de_n = 0;
        if (o_n != FRAME || t_n != FRAME) begin
            $display("COMPARE: not enough recorded (this block %0d, Terasic %0d of %0d clocks)", o_n, t_n, FRAME);
        end else begin
        for (int i = 0; i < FRAME; i++) begin
            if (ours[i][2] != theirs[i][2]) dde++;
            if (ours[i][1] != theirs[i][1]) dhs++;
            if (ours[i][0] != theirs[i][0]) dvs++;
            if (ours[i] != theirs[i] && shown < 6) begin
                shown++;
                $display("  first differences: clock %0d after vsync start (line %0d, clock %0d): this block de/hs/vs=%b  Terasic=%b",
                         i, i / HT, i % HT, ours[i], theirs[i]);
            end
            if (ours[i][1]   && o_hs_first < 0 && i > 0 && !ours[i-1][1])   o_hs_first = i;
            if (theirs[i][1] && t_hs_first < 0 && i > 0 && !theirs[i-1][1]) t_hs_first = i;
            if (ours[i][2]   && o_de_first < 0) o_de_first = i;
            if (theirs[i][2] && t_de_first < 0) t_de_first = i;
            o_vs_len += ours[i][0]; t_vs_len += theirs[i][0];
            o_de += ours[i][2];     t_de_n += theirs[i][2];
        end
        $display("COMPARE with Terasic's generator over one frame (%0d clocks), both starting at the vsync leading edge:", FRAME);
        $display("  clocks where DE differs: %0d   hsync differs: %0d   vsync differs: %0d", dde, dhs, dvs);
        $display("  first hsync start after vsync start: this block clock %0d, Terasic clock %0d", o_hs_first, t_hs_first);
        $display("  first DE: this block clock %0d (line %0d, clock %0d), Terasic clock %0d (line %0d, clock %0d)",
                 o_de_first, o_de_first / HT, o_de_first % HT, t_de_first, t_de_first / HT, t_de_first % HT);
        $display("  vsync active clocks: this block %0d, Terasic %0d   DE active clocks: this block %0d, Terasic %0d", o_vs_len, t_vs_len, o_de, t_de_n);
        $display("  sync polarity: this block pulses high (CEA-861 format 16: positive); Terasic's pulses low");
        end
    endtask

    // ---------------------------------------------------------------- end of run
    always @(posedge pix_clk) begin
        if (frame_no == frames + 1 && vid_vs && !vs_q) begin
            #1;
            $display("memory side: %0d bursts, %0d words answered, %0d clocks held off by waitrequest, %0d protocol/address errors", bursts, words, waited, mem_errors);
`ifdef TERASIC
            compare_with_terasic();
`else
            $display("COMPARE with Terasic's generator: skipped (not given; see sim/run.sh)");
`endif
            $display("RESULT: raster errors %0d, memory errors %0d, wrong pixels %0d, black pixels %0d, non-zero outside DE %0d",
                     ras_errors, mem_errors, wrong_total, black_total, blank_total);
            $finish;
        end
    end
    initial begin
        #(64'd6734 * FRAME * 8);
        $display("TIMEOUT: no end of run after 8 frame times; frame_no=%0d", frame_no);
        $finish;
    end
endmodule
