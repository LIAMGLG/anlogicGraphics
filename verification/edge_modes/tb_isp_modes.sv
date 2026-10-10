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
    reg [2:0] requested=0;
    isp_top dut (.axi4s_video_aclk(clk), .I_rst_n(rst_n), .I_key_bin(1'b1), .I_key_detect(1'b1),
        .I_tlast(last), .I_tuser(user), .I_tdata(data), .I_tvalid(valid), .I_tdest(10'd0),
        .O_tready(1'b1), .O_tdata(), .O_tlast(), .O_tuser(), .O_tvalid(), .I_tready());
    reg [95:0] expected_d1=0, expected_d2=0;
    reg valid_d1=0, valid_d2=0, user_d1=0, user_d2=0;
    reg [2:0] active_mode=0;
    reg [2:0] reference_mode_d1=0, reference_mode_d2=0;
    reg [7:0] luminance;
    reg [95:0] wanted;
    reg [23:0] gained_rgb=0,gained_rgb_d1=0;
    reg gained_valid=0,gained_user=0,gained_last=0;
    reg gained_valid_d1=0,gained_user_d1=0,gained_last_d1=0;
    function [7:0] gain_reference(input integer value,coefficient);
        integer scaled;
        begin scaled=value*coefficient/128;gain_reference=scaled>255 ? 255 : scaled;end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            gained_rgb<=0;gained_rgb_d1<=0;gained_valid<=0;gained_user<=0;gained_last<=0;
            gained_valid_d1<=0;gained_user_d1<=0;gained_last_d1<=0;
        end else begin
            gained_rgb_d1<={gain_reference(data[23:16],147),gain_reference(data[15:8],122),gain_reference(data[7:0],109)};
            gained_rgb<=gained_rgb_d1;
            gained_valid_d1<=valid;gained_user_d1<=user;gained_last_d1<=last;
            gained_valid<=gained_valid_d1;gained_user<=gained_user_d1;gained_last<=gained_last_d1;
            #1;
            if(dut.gain_data!=={4{gained_rgb}} || dut.gain_valid!==gained_valid ||
               dut.gain_user!==gained_user || dut.gain_last!==gained_last) $fatal(1,"ISP gain integration");
        end
    end
    integer frame, beat, row=0, group_index=0,gray_value;
    always @(posedge clk) begin
        if (!rst_n) begin
            expected_d1 <= 0; expected_d2 <= 0;
            valid_d1 <= 0; valid_d2 <= 0; user_d1 <= 0; user_d2 <= 0;
            active_mode = 0; row=0; group_index=0;
            reference_mode_d1 <= 0; reference_mode_d2 <= 0;
        end else begin
            if (gained_user) begin active_mode = requested; row=0; group_index=0; end
            luminance = {2'b0,gained_rgb[23:18]} + {1'b0,gained_rgb[15:9]} + {2'b0,gained_rgb[7:2]};
            case(active_mode)
                0: wanted = {4{gained_rgb}};
                1: wanted = luminance >= 64 ? {96{1'b1}} : 96'd0;
                2: wanted = 0; // two rows: Sobel windows are masked
                3: wanted = (row >= 1 && group_index > 0) ? {4{24'h55aaaa}} : 96'd0;
                4: begin
                    gray_value=(gained_rgb[23:16]+2*gained_rgb[15:8]+gained_rgb[7:0])/4;
                    wanted={12{gray_value[7:0]}};
                end
                default: wanted=96'd0;
            endcase
            expected_d1 <= wanted; expected_d2 <= expected_d1;
            reference_mode_d1 <= active_mode; reference_mode_d2 <= reference_mode_d1;
            if (gained_valid) begin
                if (gained_last) begin row=row+1; group_index=0; end
                else group_index=group_index+1;
            end
            valid_d1 <= gained_valid; valid_d2 <= valid_d1;
            user_d1 <= gained_user; user_d2 <= user_d1;
            #1;
            if (dut.edge_O_tvalid !== valid_d2 || dut.edge_O_tuser !== user_d2)
                $fatal(1,"ISP control latency mismatch");
            if (valid_d2 && dut.processed_data !== expected_d2)
                $fatal(1,"ISP mux mismatch got=%h expected=%h", dut.processed_data, expected_d2);
        end
    end
    function [15:0] golden_font(input [7:0] c, input integer r);
        reg [255:0] bitmap;
        begin
            case(c)
                8'h41: bitmap=256'h000000001c0014001400140036003e0022002200000000000000000000000000;
                8'h42: bitmap=256'h000000003e00330033003e003300330033003e00000000000000000000000000;
                8'h43: bitmap=256'h000000001e003300300030003000300033001e00000000000000000000000000;
                8'h45: bitmap=256'h000000003e00300030003e003000300030003e00000000000000000000000000;
                8'h47: bitmap=256'h000000001c003200600060006e00660036001e00000000000000000000000000;
                8'h49: bitmap=256'h000000001e000c000c000c000c000c000c001e00000000000000000000000000;
                8'h4c: bitmap=256'h0000000030003000300030003000300030003e00000000000000000000000000;
                8'h4d: bitmap=256'h0000000036003600360036002a002a0022002200000000000000000000000000;
                8'h4e: bitmap=256'h0000000033003b003b0037003300330033003300000000000000000000000000;
                8'h4f: bitmap=256'h000000001e003200630063006300630036003c00000000000000000000000000;
                8'h52: bitmap=256'h000000003e003300330033003c00360036003200000000000000000000000000;
                8'h53: bitmap=256'h000000001e00300030003c000f00030003003e00000000000000000000000000;
                8'h54: bitmap=256'h000000003f000c000c000c000c000c000c000c00000000000000000000000000;
                8'h59: bitmap=256'h00000000318013001b001e000c000c000c000c00000000000000000000000000;
                default: bitmap=0;
            endcase
            golden_font=bitmap[255-r*16 -:16];
        end
    endfunction
    integer osd_x=0, osd_y=0, osd_lane, osd_px, osd_idx;
    reg [95:0] osd_expected;
    reg [55:0] osd_text;
    reg [15:0] osd_bits;
    reg osd_expected_valid, osd_expected_user, osd_expected_last;
    always @(posedge clk) begin
        if (!rst_n) begin osd_x=0; osd_y=0; end
        else begin
            if (dut.saturation_user) begin osd_x=0; osd_y=0; end
            osd_expected=dut.saturation_data;
            osd_expected_valid=dut.saturation_valid;
            osd_expected_user=dut.saturation_user;
            osd_expected_last=dut.saturation_last;
            case(dut.saturation_mode)
                0: osd_text="NORMAL "; 1: osd_text="BINARY ";
                2: osd_text="SOBEL  "; 3: osd_text="CARTOON";
                4: osd_text="GRAY   ";
            endcase
            for(osd_lane=0;osd_lane<4;osd_lane=osd_lane+1) begin
                osd_px=osd_x+osd_lane;
                if(osd_px>=16 && osd_px<240 && osd_y>=16 && osd_y<48) begin
                    osd_idx=(osd_px-16)/32;
                    osd_bits=golden_font(osd_text[55-osd_idx*8 -:8],(osd_y-16)/2);
                    osd_expected[95-osd_lane*24 -:24]=osd_bits[15-((osd_px-16)%32)/2] ? 24'hfff200 : 24'h000000;
                end
            end
            if(osd_expected_valid) begin
                if(osd_expected_last || osd_x==1276) begin osd_x=0; osd_y=osd_y+1; end
                else osd_x=osd_x+4;
            end
            #1;
            if(dut.osd_valid!==osd_expected_valid || dut.osd_user!==osd_expected_user || dut.osd_last!==osd_expected_last)
                $fatal(1,"ISP OSD control integration");
            if(osd_expected_valid && dut.osd_data!==osd_expected)
                $fatal(1,"ISP OSD data/mode integration");
        end
    end
    initial begin
        force dut.u_key_video_mode.requested_mode = requested;
        repeat(4) @(negedge clk); rst_n=1;
        // Continuous beats and adjacent frame boundaries exercise mode/data alignment.
        for(frame=0; frame<5; frame=frame+1) begin
            requested = (frame+1)%5;
            for(beat=0; beat<32; beat=beat+1) begin
                @(negedge clk); valid=1; user=(beat==0); last=(beat%16==15);
                data = frame==2 ? 40'h00638cd3 : (beat%2 ? 40'h00f0d0e0 : 40'h00103020);
            end
        end
        // Full-width normal frame crosses the complete panel, all glyphs and edges.
        requested=0;
        for(beat=0;beat<320*50;beat=beat+1) begin
            @(negedge clk); valid=1; user=(beat==0); last=(beat%320==319);
            data=40'h00345678;
        end
        @(negedge clk); valid=0; user=0; last=0;
        repeat(4) @(negedge clk);
        $display("PASS: ISP normal/binary/edge/cartoon/gray mux, continuous beats and frame-boundary latency alignment");
        $finish;
    end
endmodule
