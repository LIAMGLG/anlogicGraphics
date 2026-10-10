`timescale 1ns/1ps
module tb_mode_osd;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, valid=0, user=0, last=0;
    reg [95:0] data=0;
    reg [2:0] mode=0;
    wire [95:0] result;
    wire ov, ou, ol;
    mode_osd_rgb96 dut (.I_clk(clk), .I_rst_n(rst_n), .I_mode(mode),
        .I_tdata(data), .I_tvalid(valid), .I_tuser(user), .I_tlast(last),
        .O_tdata(result), .O_tvalid(ov), .O_tuser(ou), .O_tlast(ol));
    integer frame, row, beat, lane, px, idx, fontrow, fontcol, yellow_count;
    reg [55:0] text;
    reg [7:0] ch;
    reg [15:0] rowbits;
    reg [95:0] expected;
    reg [23:0] pixel;
    // Golden font snapshots are generated from the supplied reference ROM,
    // independent of the DUT's indexing and rendering logic.
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

    task drive(input integer xx, input integer yy, input bit vv, input bit uu, input bit ll);
        begin
            @(negedge clk);
            valid=vv; user=uu; last=ll;
            data={24'h123456,24'h234567,24'h345678,24'h456789};
            expected=data;
            case(mode)
                0: text="NORMAL "; 1: text="BINARY ";
                2: text="SOBEL  "; 3: text="CARTOON";
                4: text="GRAY   ";
            endcase
            if(vv) begin
                for(lane=0;lane<4;lane=lane+1) begin
                    px=xx+lane;
                    if(px>=16 && px<240 && yy>=16 && yy<48) begin
                        idx=(px-16)/32;
                        ch=text[55-idx*8 -: 8];
                        fontrow=(yy-16)/2; fontcol=((px-16)%32)/2;
                        rowbits=golden_font(ch,fontrow);
                        pixel=rowbits[15-fontcol] ? 24'hfff200 : 24'h000000;
                        expected[95-lane*24 -:24]=pixel;
                        if(pixel==24'hfff200) yellow_count=yellow_count+1;
                    end
                end
            end
            @(posedge clk); #1;
            if(ov!==vv || ou!==uu || ol!==ll) $fatal(1,"OSD control alignment");
            if(vv && result!==expected)
                $fatal(1,"OSD mode=%0d x=%0d y=%0d got=%h expected=%h",mode,xx,yy,result,expected);
        end
    endtask
    initial begin
        yellow_count=0;
        repeat(3) @(negedge clk); rst_n=1;
        // Whole rows around all panel edges; every character and all four modes.
        // Alternating SOF with first data / SOF before data, plus valid gaps.
        for(frame=0;frame<5;frame=frame+1) begin
            mode=frame;
            if(frame%2) drive(0,0,0,1,0);
            for(row=0;row<50;row=row+1) begin
                for(beat=0;beat<320;beat=beat+1) begin
                    drive(beat*4,row,1,frame%2==0 && row==0 && beat==0,beat==319);
                    if(frame%2 && beat%71==0) drive(0,0,0,0,0);
                end
            end
        end
        // Reset after partial frame; no stale coordinates or valid/SOF.
        @(negedge clk); rst_n=0; #1;
        if(ov!==0 || ou!==0 || ol!==0 || result!==0) $fatal(1,"OSD reset");
        @(negedge clk); rst_n=1; mode=0;
        drive(0,0,1,1,0);
        if(yellow_count==0) $fatal(1,"OSD text missing");
        $display("PASS: mode OSD five labels, pixel lanes, panel edges, SOF, gaps, reset and one-cycle control alignment");
        $finish;
    end
    initial begin #2000000; $fatal(1,"OSD timeout"); end
endmodule
