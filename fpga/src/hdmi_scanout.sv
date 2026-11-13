// HDMI scan-out for the DE25-Nano: outputs 1920x1080, 60 Hz video from a frame buffer in system
// RAM on the board's ADV7513 HDMI transmitter.
//
// Frame buffer: 1920 x 1080 pixels, 4 bytes each (x8r8g8b8: blue in the lowest byte), rows top to
// bottom with no padding, at the fixed byte address FB_BASE. It is read through an Avalon
// memory-mapped port with 256-bit data (8 pixels a word), in bursts of 16 words.
//
// Two clock domains: mem_clk (the memory port) and pix_clk (148.5 MHz). The reader fills a FIFO
// one frame at a time; the pixel side empties it. In every vertical blanking interval the two
// sides restart by a handshake: the pixel side raises "flush"; the reader stops asking, lets
// outstanding reads finish, resets its write pointer and answers "ack"; the pixel side then
// resets its read pointer and drops "flush"; the reader starts the next frame from FB_BASE.
// So a frame that ran short of data (shown as black from that point) cannot disturb the next
// one. If the answer comes too late in the blanking for the FIFO to fill, the next frame is
// black and the restart happens in the blanking after it. The raster never stops.
//
// The FIFO holds 2**AW words of 8 pixels: by default 4096 words, about 17 lines or 220
// microseconds of video, so that delays on the memory port (the CPU uses the same memory)
// do not empty it. With 128 words (7 microseconds) the display flickered or went black below
// some line whenever Linux was busy writing to memory.
//
// No registers: the output is whatever is in memory at FB_BASE.

module hdmi_scanout #(
    parameter logic [31:0] FB_BASE = 32'hBF00_0000,
    parameter int          AW      = 12            // FIFO of 2**AW words
) (
    // memory side
    input  logic         mem_clk,
    input  logic         mem_reset_n,
    output logic [26:0]  mem_address,      // in 32-byte words
    output logic [4:0]   mem_burstcount,
    output logic         mem_read,
    input  logic [255:0] mem_readdata,
    input  logic         mem_readdatavalid,
    input  logic         mem_waitrequest,
    // pixel side
    input  logic         pix_clk,
    input  logic         pix_pll_locked,
    output logic [23:0]  vid_d,            // {red, green, blue}
    output logic         vid_de,
    output logic         vid_hs,
    output logic         vid_vs,
    output logic         dbg_bad           // this frame ran out of data (pix_clk domain)
);
    // 1920x1080 at 60 Hz (CEA-861 format 16), both syncs positive
    localparam int H_ACTIVE = 1920, H_FP = 88, H_SYNC = 44, H_TOTAL = 2200;
    localparam int V_ACTIVE = 1080, V_FP = 4,  V_SYNC = 5,  V_TOTAL = 1125;
    // end-of-frame restart: requested at the start of line FLUSH_ON; the read side restarts when
    // the memory side has answered, but not from line FLUSH_LAST on (too close to the next frame)
    localparam int FLUSH_ON = V_ACTIVE + 1, FLUSH_LAST = V_TOTAL - 8;

    localparam int BURST = 16;
    localparam int FRAME_WORDS = H_ACTIVE * V_ACTIVE / 8;   // 259200, a multiple of BURST
    localparam int DEPTH = 1 << AW;

    function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
        logic [AW:0] b;
        b[AW] = g[AW];
        for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    // ---------------------------------------------------------------- FIFO storage and pointers
    logic [255:0] fifo_mem [0:DEPTH-1];   // block RAM: written on mem_clk, read on pix_clk
    logic [AW:0]  wbin, wgray;          // mem_clk
    logic [AW:0]  rbin, rgray;          // pix_clk
    logic [AW:0]  rgray_m1, rgray_m2;   // read pointer seen from mem_clk
    logic [AW:0]  wgray_p1, wgray_p2;   // write pointer seen from pix_clk
    logic         flush_pix;            // pix_clk
    logic         flush_m1, flush_m2;   // seen from mem_clk
    logic         flush_ack;            // mem_clk: write side stopped and reset, read side may restart
    logic         ack_p1, ack_p2;       // seen from pix_clk

    // ---------------------------------------------------------------- memory side (mem_clk)
    logic        fifo_wr;
    logic        flush_m3, flush_m4;
    logic        armed;                 // the frame is running: bursts may be requested
    logic [18:0] words_left;            // words of this frame not yet requested
    logic [AW:0] outstanding;           // words requested and not yet received
    logic [26:0] next_addr;
    logic [AW:0] wused;

    assign wused = wbin - gray2bin(rgray_m2);
    assign mem_burstcount = BURST[4:0];

    always_ff @(posedge mem_clk) begin
        if (fifo_wr) fifo_mem[wbin[AW-1:0]] <= mem_readdata;
    end

    always_ff @(posedge mem_clk) begin
        rgray_m1 <= rgray;       rgray_m2 <= rgray_m1;
        flush_m1 <= flush_pix;   flush_m2 <= flush_m1;
    end

    wire burst_accepted = mem_read && !mem_waitrequest;
    wire running = armed && !flush_m2;
    assign fifo_wr = mem_readdatavalid && running;

    always_ff @(posedge mem_clk) begin
        flush_m3 <= flush_m2; flush_m4 <= flush_m3;
        if (!mem_reset_n) begin
            wbin <= '0; wgray <= '0;
            mem_read <= 1'b0; mem_address <= '0;
            armed <= 1'b0; flush_ack <= 1'b0; words_left <= '0; outstanding <= '0; next_addr <= '0;
        end else begin
            // words on their way
            case ({burst_accepted, mem_readdatavalid})
                2'b10:   outstanding <= outstanding + (AW+1)'(BURST);
                2'b01:   outstanding <= outstanding - 1'b1;
                2'b11:   outstanding <= outstanding + (AW+1)'(BURST - 1);
                default: ;
            endcase

            if (burst_accepted) mem_read <= 1'b0;

            if (fifo_wr) begin
                wbin  <= wbin + 1'b1;
                wgray <= (wbin + 1'b1) ^ ((wbin + 1'b1) >> 1);
            end

            if (flush_m2 && !flush_m3) begin
                // a flush begins: the frame is over, whatever state it was in
                armed <= 1'b0; flush_ack <= 1'b0;
            end else if (flush_m2) begin
                // let reads in flight finish, however long they take, then reset for the next
                // frame and tell the pixel side
                if (!flush_ack && !armed && !mem_read && outstanding == 0 && !mem_readdatavalid) begin
                    wbin <= '0; wgray <= '0;
                    next_addr  <= FB_BASE[31:5];
                    words_left <= 19'(FRAME_WORDS);
                    flush_ack  <= 1'b1;
                end
            end else if (flush_ack) begin
                // the pixel side has reset its read pointer and dropped the flush. Wait until the
                // new read pointer has settled on this side (it is not a one-bit gray step), then run.
                if (!flush_m3 && !flush_m4) begin
                    armed <= 1'b1; flush_ack <= 1'b0;
                end
            end else if (armed) begin
                // request the next burst when the FIFO has room for it and for all words on their way
                if (!mem_read && words_left != 0 &&
                    (32'(wused) + 32'(outstanding) + BURST <= DEPTH - 2)) begin
                    mem_read    <= 1'b1;
                    mem_address <= next_addr;
                    next_addr   <= next_addr + 27'(BURST);
                    words_left  <= words_left - 19'(BURST);
                end
            end
        end
    end

    // ---------------------------------------------------------------- pixel side (pix_clk)
    logic        pix_rst;
    logic [2:0]  pix_rst_sr;
    always_ff @(posedge pix_clk or negedge pix_pll_locked) begin
        if (!pix_pll_locked) pix_rst_sr <= 3'b111;
        else                 pix_rst_sr <= {pix_rst_sr[1:0], 1'b0};
    end
    assign pix_rst = pix_rst_sr[2];

    logic [11:0] hcnt;
    logic [10:0] vcnt;
    logic [2:0]  px;                    // pixel within the 256-bit word
    logic        bad;                   // ran out of data in this frame: black until the next one
    logic        fifo_rd;

    always_ff @(posedge pix_clk) begin
        wgray_p1 <= wgray;  wgray_p2 <= wgray_p1;
        ack_p1 <= flush_ack; ack_p2 <= ack_p1;
    end
    wire         rempty  = (rgray == wgray_p2);
    wire         active  = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
    wire         show    = active && !bad && !rempty;
    assign fifo_rd = show && (px == 3'd7);
    assign dbg_bad = bad;
    // it has answered the flush, and there is time for the FIFO to fill before line 0: restart
    wire         restart = flush_pix && ack_p2 && (vcnt > FLUSH_ON) && (vcnt < FLUSH_LAST);
    // The read pointer's next value is formed here so that the RAM's read address can be a
    // register of its own (raddr_q, always equal to rbin): a block RAM needs a registered address.
    wire [AW:0]  rbin_n  = (pix_rst || restart) ? '0 : fifo_rd ? rbin + 1'b1 : rbin;
    logic [AW-1:0] raddr_q;
    always_ff @(posedge pix_clk) begin
        rbin    <= rbin_n;
        rgray   <= rbin_n ^ (rbin_n >> 1);
        raddr_q <= rbin_n[AW-1:0];
    end
    wire [255:0] rword   = fifo_mem[raddr_q];

    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            hcnt <= '0; vcnt <= 11'(V_ACTIVE);   // start in the blanking, so a flush comes first
            px <= '0; bad <= 1'b1; flush_pix <= 1'b0;
            vid_d <= '0; vid_de <= 1'b0; vid_hs <= 1'b0; vid_vs <= 1'b0;
        end else begin
            // raster counters
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= '0;
                vcnt <= (vcnt == V_TOTAL - 1) ? '0 : vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end

            // pixel within the word, and running out of data
            if (active) begin
                if (show) px <= px + 1'b1;
                else      bad <= 1'b1;
            end

            // end of frame (in the vertical blanking, so nothing above touches these): ask the
            // memory side to stop and reset; the frame after this one is black unless it answers
            if (hcnt == 0 && vcnt == FLUSH_ON) begin
                flush_pix <= 1'b1; bad <= 1'b1;
            end
            if (restart) begin
                px <= '0; bad <= 1'b0; flush_pix <= 1'b0;
            end

            // outputs, one clock after the counters
            vid_de <= active;
            vid_d  <= show ? rword[32*px +: 24] : 24'h0;
            vid_hs <= (hcnt >= H_ACTIVE + H_FP) && (hcnt < H_ACTIVE + H_FP + H_SYNC);
            // CEA-861: the vertical sync changes together with the leading edge of the horizontal
            // sync (not at the start of the active part of a line, as it did at first). It rises
            // at the hsync edge that ends the last front porch line and lasts V_SYNC lines.
            if (hcnt == H_ACTIVE + H_FP) begin
                if (vcnt == V_ACTIVE + V_FP - 1)               vid_vs <= 1'b1;
                else if (vcnt == V_ACTIVE + V_FP + V_SYNC - 1) vid_vs <= 1'b0;
            end
        end
    end
endmodule
