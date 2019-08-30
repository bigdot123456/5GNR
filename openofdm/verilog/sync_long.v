module sync_long (
    input clock,
    input reset,
    input enable,

    input set_stb,
    input [7:0] set_addr,
    input [31:0] set_data,

    input [31:0] sample_in,
    input sample_in_strobe,
    input signed [31:0] phase_offset,
    input short_gi,

    output [`ROTATE_LUT_LEN_SHIFT-1:0] rot_addr,
    input [31:0] rot_data,

    output [31:0] metric,
    output metric_stb,
    output reg long_preamble_detected,

    output reg [31:0] sample_out,
    output reg sample_out_strobe,

    output reg [2:0] state
);
`include "common_params.v"

localparam IN_BUF_LEN_SHIFT = 8;

localparam NUM_STS_TAIL = 32;

reg [15:0] in_offset;
reg [IN_BUF_LEN_SHIFT-1:0] in_waddr;
reg [IN_BUF_LEN_SHIFT-1:0] in_raddr;
wire [IN_BUF_LEN_SHIFT-1:0] gi_skip = short_gi? 9: 17;
reg signed [31:0] num_input_produced;
reg signed [31:0] num_input_consumed;
reg signed [31:0] num_input_avail;

reg [2:0] mult_stage;
reg [1:0] sum_stage;
reg  mult_strobe;

wire signed [31:0] stage_sum_i;
wire signed [31:0] stage_sum_q;

wire stage_sum_stb;

reg signed [31:0] sum_i;
reg signed [31:0] sum_q;
reg sum_stb;

reg signed [31:0] phase_correction;
reg signed [31:0] next_phase_correction;


complex_to_mag #(.DATA_WIDTH(32)) sum_mag_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .i(sum_i),
    .q(sum_q),
    .input_strobe(sum_stb),

    .mag(metric),
    .mag_stb(metric_stb)
);

reg [31:0] metric_max1;
reg [(IN_BUF_LEN_SHIFT-1):0] addr1;
reg [31:0] metric_max2;
reg [(IN_BUF_LEN_SHIFT-1):0] addr2;
reg [15:0] gap;

reg [31:0] cross_corr_buf[0:15];

reg [31:0] stage_X0;
reg [31:0] stage_X1;
reg [31:0] stage_X2;
reg [31:0] stage_X3;

reg [31:0] stage_Y0;
reg [31:0] stage_Y1;
reg [31:0] stage_Y2;
reg [31:0] stage_Y3;

stage_mult stage_mult_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .X0(stage_X0[31:16]),
    .X1(stage_X0[15:0]),
    .X2(stage_X1[31:16]),
    .X3(stage_X1[15:0]),
    .X4(stage_X2[31:16]),
    .X5(stage_X2[15:0]),
    .X6(stage_X3[31:16]),
    .X7(stage_X3[15:0]),

    .Y0(stage_Y0[31:16]),
    .Y1(stage_Y0[15:0]),
    .Y2(stage_Y1[31:16]),
    .Y3(stage_Y1[15:0]),
    .Y4(stage_Y2[31:16]),
    .Y5(stage_Y2[15:0]),
    .Y6(stage_Y3[31:16]),
    .Y7(stage_Y3[15:0]),

    .input_strobe(mult_strobe),

    .sum({stage_sum_i, stage_sum_q}),
    .output_strobe(stage_sum_stb)
);

localparam S_SKIPPING = 0;
localparam S_WAIT_FOR_FIRST_PEAK = 1;
localparam S_WAIT_FOR_SECOND_PEAK = 2;
localparam S_IDLE = 3;
localparam S_FFT = 4;

reg fft_start;
wire fft_start_delayed;
wire fft_in_stb;
reg fft_loading;
wire signed [15:0] fft_in_re;
wire signed [15:0] fft_in_im;
wire [22:0] fft_out_re;
wire [22:0] fft_out_im;
wire fft_ready;
wire fft_done;
wire fft_busy;
wire fft_valid;

wire [31:0] fft_out = {fft_out_re[22:7], fft_out_im[22:7]};

wire signed [15:0] raw_i;
wire signed [15:0] raw_q;
reg raw_stb;

ram_2port  #(.DWIDTH(32), .AWIDTH(IN_BUF_LEN_SHIFT)) in_buf (
    .clka(clock),
    .ena(1),
    .wea(sample_in_strobe),
    .addra(in_waddr),
    .dia(sample_in),
    .doa(),
    .clkb(clock),
    .enb(fft_start | fft_loading),
    .web(1'b0),
    .addrb(in_raddr),
    .dib(32'hFFFF),
    .dob({raw_i, raw_q})
);

rotate rotate_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .in_i(raw_i),
    .in_q(raw_q),
    .phase(phase_correction),
    .input_strobe(raw_stb),

    .rot_addr(rot_addr),
    .rot_data(rot_data),
    
    .out_i(fft_in_re),
    .out_q(fft_in_im),
    .output_strobe(fft_in_stb)
);

delayT #(.DATA_WIDTH(1), .DELAY(9)) fft_delay_inst (
    .clock(clock),
    .reset(reset),

    .data_in(fft_start),
    .data_out(fft_start_delayed)
);


xfft_v7_1 dft_inst (
    .clk(clock),
    .fwd_inv(1),
    .start(fft_start_delayed),
    .fwd_inv_we(1),

    .xn_re(fft_in_re),
    .xn_im(fft_in_im),
    .xk_re(fft_out_re),
    .xk_im(fft_out_im),
    .rfd(fft_ready),
    .done(fft_done),
    .busy(fft_busy),
    .dv(fft_valid)
);

reg [15:0] num_sample;
reg [15:0] num_ofdm_symbol;

integer i;
integer j;
always @(posedge clock) begin
    if (reset) begin
        for (j = 0; j < 16; j= j+1) begin
            cross_corr_buf[j] <= 0;
        end
        do_clear();
        state <= S_SKIPPING;
    end else if (enable) begin
        if (sample_in_strobe && state != S_SKIPPING) begin
            in_waddr <= in_waddr + 1;
            num_input_produced <= num_input_produced + 1;
        end
        num_input_avail <= num_input_produced - num_input_consumed;

        case(state)
            S_SKIPPING: begin
                // skip the tail of  short preamble
                if (num_sample >= NUM_STS_TAIL) begin
                    num_sample <= 0;
                    state <= S_WAIT_FOR_FIRST_PEAK;
                end else if (sample_in_strobe) begin
                    num_sample <= num_sample + 1;
                end
            end

            S_WAIT_FOR_FIRST_PEAK: begin
                do_mult();

                if (metric_stb && (metric > metric_max1)) begin
                    metric_max1 <= metric;
                    addr1 <= in_raddr - 1;
                end

                if (num_sample >= 64) begin
                    num_sample <= 0;
                    addr2 <= 0;
                    state <= S_WAIT_FOR_SECOND_PEAK;
                end else if (metric_stb) begin
                    num_sample <= num_sample + 1;
                end

            end

            S_WAIT_FOR_SECOND_PEAK: begin
                do_mult();

                if (metric_stb && (metric > metric_max2)) begin
                    metric_max2 <= metric;
                    addr2 <= in_raddr - 1;
                end
                gap <= addr2 - addr1;

                if (num_sample >= 64) begin
                    `ifdef DEBUG_PRINT
                        $display("PEAK GAP: %d (%d - %d)", gap, addr2, addr1);
                        $display("PHASE OFFSET: %d", phase_offset);
                    `endif
                    if (gap > 62 && gap < 66) begin
                        long_preamble_detected <= 1;
                        num_sample <= 0;
                        mult_strobe <= 0;
                        sum_stb <= 0;
                        // offset it by the length of cross correlation buffer
                        // size
                        in_raddr <= addr1 - 16;
                        num_input_consumed <= addr1 - 16;
                        in_offset <= 0;
                        num_ofdm_symbol <= 0;
                        phase_correction <= 0;
                        next_phase_correction <= phase_offset;
                        state <= S_FFT;
                    end else begin
                        state <= S_IDLE;
                    end
                end else if (metric_stb) begin
                    num_sample <= num_sample + 1;
                end
            end

            S_FFT: begin
                if (long_preamble_detected) begin
                    `ifdef DEBUG_PRINT
                        $display("Long preamble detected");
                    `endif
                    long_preamble_detected <= 0;
                end

                if (~fft_loading && num_input_avail > 64) begin
                    fft_start <= 1;
                    in_offset <= 0;
                end

                if (fft_start) begin
                    fft_start <= 0;
                    fft_loading <= 1;
                end

                raw_stb <= fft_start | fft_loading;
                if (raw_stb) begin
                    if (phase_offset > 0) begin
                        if (next_phase_correction > PI) begin
                            phase_correction <= next_phase_correction - DOUBLE_PI;
                            next_phase_correction <= next_phase_correction + phase_offset - DOUBLE_PI;
                        end else begin
                            phase_correction <= next_phase_correction;
                            next_phase_correction <= next_phase_correction + phase_offset;
                        end
                    end else begin
                        if (next_phase_correction < -PI) begin
                            phase_correction <= next_phase_correction + DOUBLE_PI;
                            phase_correction <= next_phase_correction + DOUBLE_PI + phase_offset;
                        end else begin
                            phase_correction <= next_phase_correction;
                            phase_correction <= next_phase_correction + phase_offset;
                        end
                    end
                end

                if (fft_start | fft_loading) begin
                    in_offset <= in_offset + 1;

                    if (in_offset == 63) begin
                        fft_loading <= 0;
                        num_ofdm_symbol <= num_ofdm_symbol + 1;
                        if (num_ofdm_symbol > 0) begin
                            // skip the Guard Interval for data symbols
                            in_raddr <= in_raddr + gi_skip;
                            num_input_consumed <= num_input_consumed + gi_skip;
                        end else begin
                            in_raddr <= in_raddr + 1;
                            num_input_consumed <= num_input_consumed + 1;
                        end
                    end else begin
                        in_raddr <= in_raddr + 1;
                        num_input_consumed <= num_input_consumed + 1;
                    end
                end

                sample_out_strobe <= fft_valid;
                sample_out <= fft_out;
            end

            S_IDLE: begin
            end

            default: begin
                state <= S_WAIT_FOR_FIRST_PEAK;
            end
        endcase
    end else begin
        sample_out_strobe <= 0;
    end
end

integer do_mult_i;
task do_mult; begin
    // cross correlation of the first 16 samples of LTS
    if (sample_in_strobe) begin
        cross_corr_buf[15] <= sample_in;
        for (do_mult_i = 0; do_mult_i < 15; do_mult_i = do_mult_i+1) begin
            cross_corr_buf[do_mult_i] <= cross_corr_buf[do_mult_i+1];
        end

        sum_stage <= 0;
        sum_i <= 0;
        sum_q <= 0;
        sum_stb <= 0;

        stage_X0 <= cross_corr_buf[1];
        stage_X1 <= cross_corr_buf[2];
        stage_X2 <= cross_corr_buf[3];
        stage_X3 <= cross_corr_buf[4];

        stage_Y0[31:16] <= 156;
        stage_Y0[15:0] <= 0;
        stage_Y1[31:16] <= -5;
        stage_Y1[15:0] <= 120;
        stage_Y2[31:16] <= 40;
        stage_Y2[15:0] <= 111;
        stage_Y3[31:16] <= 97;
        stage_Y3[15:0] <= -83;

        mult_strobe <= 1;
        mult_stage <= 1;
    end

    if (mult_stage == 1) begin
        stage_X0 <= cross_corr_buf[4];
        stage_X1 <= cross_corr_buf[5];
        stage_X2 <= cross_corr_buf[6];
        stage_X3 <= cross_corr_buf[7];

        stage_Y0[31:16] <= 21;
        stage_Y0[15:0] <= -28;
        stage_Y1[31:16] <= 60;
        stage_Y1[15:0] <= 88;
        stage_Y2[31:16] <= -115;
        stage_Y2[15:0] <= 55;
        stage_Y3[31:16] <= -38;
        stage_Y3[15:0] <= 106;

        mult_stage <= 2;
    end else if (mult_stage == 2) begin
        stage_X0 <= cross_corr_buf[8];
        stage_X1 <= cross_corr_buf[9];
        stage_X2 <= cross_corr_buf[10];
        stage_X3 <= cross_corr_buf[11];

        stage_Y0[31:16] <= 98;
        stage_Y0[15:0] <= 26;
        stage_Y1[31:16] <= 53;
        stage_Y1[15:0] <= -4;
        stage_Y2[31:16] <= 1;
        stage_Y2[15:0] <= 115;
        stage_Y3[31:16] <= -137;
        stage_Y3[15:0] <= 47;

        mult_stage <= 3;
    end else if (mult_stage == 3) begin
        stage_X0 <= cross_corr_buf[12];
        stage_X1 <= cross_corr_buf[13];
        stage_X2 <= cross_corr_buf[14];
        stage_X3 <= cross_corr_buf[15];

        stage_Y0[31:16] <= 24;
        stage_Y0[15:0] <= 59;
        stage_Y1[31:16] <= 59;
        stage_Y1[15:0] <= 15;
        stage_Y2[31:16] <= -22;
        stage_Y2[15:0] <= -161;
        stage_Y3[31:16] <= 119;
        stage_Y3[15:0] <= 4;

        mult_stage <= 4;
    end else if (mult_stage == 4) begin
        mult_stage <= 0;
        mult_strobe <= 0;
        in_raddr <= in_raddr + 1;
        num_input_consumed <= num_input_consumed + 1;
    end

    if (stage_sum_stb) begin
        sum_stage <= sum_stage + 1;
        sum_i <= sum_i + stage_sum_i;
        sum_q <= sum_q + stage_sum_q;
        if (sum_stage == 3) begin
            sum_stb <= 1;
        end
    end else begin
        sum_stb <= 0;
        sum_i <= 0;
        sum_q <= 0;
    end
end
endtask

task do_clear; begin
    gap <= 0;

    in_waddr <= 0;
    in_raddr <= 0;
    in_offset <= 0;
    num_input_produced <= 0;
    num_input_consumed <= 0;
    num_input_avail <= 0;

    phase_correction <= 0;
    next_phase_correction <= 0;

    raw_stb <= 0;

    sum_i <= 0;
    sum_q <= 0;
    sum_stb <= 0;
    sum_stage <= 0;
    mult_strobe <= 0;

    metric_max1 <= 0;
    addr1 <= 0;
    metric_max2 <= 0;
    addr2 <= 0;

    mult_stage <= 0;

    long_preamble_detected <= 0;
    num_sample <= 0;
    num_ofdm_symbol <= 0;

    fft_start <= 0;
    fft_loading <= 0;

    sample_out_strobe <= 0;
    sample_out <= 0;

    stage_X0 <= 0;
    stage_X1 <= 0;
    stage_X2 <= 0;
    stage_X3 <= 0;

    stage_Y0 <= 0;
    stage_Y1 <= 0;
    stage_Y2 <= 0;
    stage_Y3 <= 0;
end
endtask

endmodule
