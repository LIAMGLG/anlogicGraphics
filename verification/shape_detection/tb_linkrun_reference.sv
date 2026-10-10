`timescale 1ns/1ps
// Upstream LinkRunCCA smoke test on unmodified RTL: separated rectangles.
module tb_linkrun_reference;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,valid=0,pixel=0;
    wire ov;
    wire [23:0] box;
    LinkRunCCA #(.imwidth(64),.imheight(48)) upstream (
        .clk(clk),.rst(rst),.datavalid(valid),.pix_in(pixel),.datavalid_out(ov),.box_out(box));
    integer frame,x,y,found=0;
    reg [23:0] expected0={6'd5,6'd14,6'd5,6'd14};
    reg [23:0] expected1={6'd35,6'd49,6'd24,6'd35};
    always @(posedge clk) begin
        #1;
        if(valid && ov) begin
            if(box===expected0) found=found|1;
            else if(box===expected1) found=found|2;
            else $fatal(1,"Unexpected upstream bbox %h",box);
        end
    end
    initial begin
        // Reproduce the upstream Verilator harness's zero-initialized RAM environment.
        for(integer init=0;init<32;init=init+1) begin
            upstream.Next_Table.ram[init]=0;upstream.Head_Table.ram[init]=0;
            upstream.Tail_Table.ram[init]=0;upstream.Data_Table.ram[init]=0;
        end
        repeat(4) @(negedge clk);rst=0;
        // Blank frames initialize upstream row shift registers and flush results.
        for(frame=0;frame<3;frame=frame+1)
            for(y=0;y<48;y=y+1) for(x=0;x<64;x=x+1) begin
                @(negedge clk);valid=1;
                pixel=frame==1 && ((x>=5 && x<=14 && y>=5 && y<=14) ||
                                                  (x>=35 && x<=49 && y>=24 && y<=35));
            end
        @(negedge clk);valid=0;
        if(found!=3) $fatal(1,"Upstream reference missing boxes found=%0d",found);
        $display("PASS: unmodified LinkRunCCA reference bounding boxes on separated rectangles");
        $finish;
    end
endmodule
