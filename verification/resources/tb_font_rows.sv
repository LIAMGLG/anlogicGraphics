`timescale 1ns/1ps
module tb_font_rows;
    reg [7:0] ch;
    reg [3:0] row;
    wire [15:0] bits;
    reg [255:0] bitmap;
    integer c,r;
    osd_char_lib dut(.I_char(ch),.I_row(row),.O_row_bits(bits));
    `include "verification/resources/original_font.vh"
    initial begin
        for(c=0;c<256;c=c+1) for(r=0;r<16;r=r+1) begin
            ch=c;row=r;bitmap=original_bitmap(ch);#1;
            if(bits!==bitmap[255-r*16 -:16])
                $fatal(1,"Font changed: char=%h row=%0d",ch,r);
        end
        $display("PASS: all 4096 character/row combinations match original font");
        $finish;
    end
endmodule
