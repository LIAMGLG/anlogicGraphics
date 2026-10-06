`timescale 1ns/1ps
// Upstream-only simulation substitutes: test the ISP mode mux and latency
// without modelling RAW demosaic or AWB arithmetic.
module demosaic #(parameter IMG_HEIGHT=720, IMG_WIDTH=1280, data_complete_delay=50, BAYER_MODE="BGGR") (
    input I_clk, I_rst_n, input [39:0] axi4s_video_tdata, input [9:0] axi4s_video_tdest,
    input axi4s_video_tlast, axi4s_video_tvalid, axi4s_video_tuser,
    output axi4s_video_tready, output O_tlast, O_tuser, output [127:0] O_tdata,
    output O_tvalid, input O_tready
);
    assign O_tdata = {4{8'd0,axi4s_video_tdata[23:0]}};
    assign O_tlast = axi4s_video_tlast;
    assign O_tuser = axi4s_video_tuser;
    assign O_tvalid = axi4s_video_tvalid;
    assign axi4s_video_tready = O_tready;
endmodule
module awb #(parameter IMG_HEIGHT=720, IMG_WIDTH=1280) (
    input I_clk, I_rst_n, I_tlast, I_tuser, input [95:0] I_tdata, input I_tvalid,
    output I_tready, output O_tlast, O_tuser, output [95:0] O_tdata,
    output O_tvalid, input O_tready
);
    assign O_tlast=I_tlast; assign O_tuser=I_tuser;
    assign O_tdata=I_tdata; assign O_tvalid=I_tvalid;
    assign I_tready=O_tready;
endmodule
module tb_isp_modes;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, valid=0, user=0, last=0;
    reg [39:0] data=0;
    reg [1:0] requested=0;
    isp_top dut (.axi4s_video_aclk(clk), .I_rst_n(rst_n), .I_key_bin(1'b1), .I_adjust_enable(1'b0), .I_key_threshold(1'b1), .I_key_edge(1'b1),
        .I_tlast(last), .I_tuser(user), .I_tdata(data), .I_tvalid(valid), .I_tdest(10'd0),
        .O_tready(1'b1), .O_tdata(), .O_tlast(), .O_tuser(), .O_tvalid(), .I_tready());
    reg [95:0] expected_d1=0, expected_d2=0;
    reg valid_d1=0, valid_d2=0, user_d1=0, user_d2=0;
    reg [1:0] active_mode=0;
    reg [7:0] luminance;
    reg [95:0] wanted;
    integer frame, beat, row=0, group_index=0;
    always @(posedge clk) begin
        if (!rst_n) begin
            expected_d1 <= 0; expected_d2 <= 0;
            valid_d1 <= 0; valid_d2 <= 0; user_d1 <= 0; user_d2 <= 0;
            active_mode = 0; row=0; group_index=0;
        end else begin
            if (user) begin active_mode = requested; row=0; group_index=0; end
            luminance = {2'b0,data[23:18]} + {1'b0,data[15:9]} + {2'b0,data[7:2]};
            case(active_mode)
                0: wanted = {4{data[23:0]}};
                1: wanted = luminance >= 64 ? {96{1'b1}} : 96'd0;
                2: wanted = 0; // two rows: Sobel windows are masked
                3: wanted = (row >= 1 && group_index > 0) ? {4{24'h55aaff}} : 96'd0;
            endcase
            expected_d1 <= wanted; expected_d2 <= expected_d1;
            if (valid) begin
                if (last) begin row=row+1; group_index=0; end
                else group_index=group_index+1;
            end
            valid_d1 <= valid; valid_d2 <= valid_d1;
            user_d1 <= user; user_d2 <= user_d1;
            #1;
            if (dut.edge_O_tvalid !== valid_d2 || dut.edge_O_tuser !== user_d2)
                $fatal(1,"ISP control latency mismatch");
            if (valid_d2 && dut.processed_data !== expected_d2)
                $fatal(1,"ISP mux mismatch got=%h expected=%h", dut.processed_data, expected_d2);
        end
    end
    initial begin
        force dut.u_key_video_mode.requested_mode = requested;
        repeat(4) @(negedge clk); rst_n=1;
        // Continuous beats and adjacent frame boundaries exercise mode/data alignment.
        for(frame=0; frame<4; frame=frame+1) begin
            requested = (frame+1)%4;
            for(beat=0; beat<32; beat=beat+1) begin
                @(negedge clk); valid=1; user=(beat==0); last=(beat%16==15);
                data = frame==2 ? 40'h00638cd3 : (beat%2 ? 40'h00f0d0e0 : 40'h00103020);
            end
        end
        @(negedge clk); valid=0; user=0; last=0;
        repeat(4) @(negedge clk);
        $display("PASS: ISP normal/binary/edge/cartoon mux, continuous beats and frame-boundary latency alignment");
        $finish;
    end
endmodule
