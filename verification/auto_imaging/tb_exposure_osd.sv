`timescale 1ns/1ps
module tb_exposure_osd;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,user=0,valid=0,last=0;
    reg [29:0] status=30'h11660100;
    wire [95:0] result;
    wire ov,ou,ol;
    mode_osd_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_mode(3'd3),.I_exposure_status(status),
        .I_tdata({4{24'h123456}}),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
        .O_tdata(result),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol));
    reg [135:0] text_value="AE 16.6MS G01.00X";
    reg [7:0] ch;
    reg [3:0] font_row;
    wire [15:0] row_bits;
    osd_char_lib reference_font(.I_char(ch),.I_row(font_row),.O_row_bits(row_bits));
    integer y,x,lane,px,index,col,dots=0;
    reg [15:0] reference_row;
    reg [23:0] expected;
    initial begin
        repeat(4) @(negedge clk);rst=1;user=1;
        @(negedge clk);user=0;
        for(y=0;y<48;y=y+1) for(x=0;x<320;x=x+1) begin
            valid=1;last=x==319;
            // Mid-frame updates must not tear the displayed number.
            if(y==20) status=30'h11230200;
            @(posedge clk);#1;
            if(!ov || ol!==last || ou) $fatal(1,"OSD control alignment");
            if(y>=16 && x*4>=256 && x*4<800) begin
                index=(x*4-256)/32;ch=text_value[135-index*8 -:8];font_row=(y-16)/2;
                #1;reference_row=ch=="." ? ((font_row==11 || font_row==12) ? 16'h0180:0):row_bits;
                for(lane=0;lane<4;lane=lane+1) begin
                    px=x*4+lane;col=((px-256)%32)/2;
                    expected=reference_row[15-col] ? 24'hfff200:24'h000000;
                    if(result[95-lane*24 -:24]!==expected) $fatal(1,"exposure OSD pixel %d %d",px,y);
                    if(ch=="." && expected==24'hfff200) dots=dots+1;
                end
            end
            @(negedge clk);
        end
        if(dots!=32) $fatal(1,"missing decimal points %d",dots);
        $display("PASS: exposure OSD digits, decimal points, frame latch and stream alignment");$finish;
    end
endmodule
