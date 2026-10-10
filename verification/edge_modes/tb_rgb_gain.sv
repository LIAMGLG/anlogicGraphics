`timescale 1ns/1ps
module tb_rgb_gain;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0;
    reg [95:0] data=0;
    wire [95:0] result;wire ov,ou,ol;
    color_gain_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_tdata(data),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
        .O_tdata(result),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol));
    function [7:0] golden(input integer value,coeff);
        integer scaled;
        begin scaled=value*coeff/128;golden=scaled>255 ? 255 : scaled;end
    endfunction
    reg [95:0] expected=0,e0=0,e1=0;
    reg v0=0,v1=0,u0=0,u1=0,l0=0,l1=0;
    integer lane,n,pass,checks=0;
    always @(*) begin
        expected=0;
        for(integer p=0;p<4;p=p+1)
            expected[95-p*24 -:24]={golden(data[95-p*24 -:8],147),golden(data[87-p*24 -:8],122),golden(data[79-p*24 -:8],109)};
    end
    always @(posedge clk) begin
        if(!rst) begin e0<=0;e1<=0;v0<=0;v1<=0;u0<=0;u1<=0;l0<=0;l1<=0;end
        else begin
            e0<=expected;e1<=e0;v0<=valid;v1<=v0;u0<=user;u1<=u0;l0<=last;l1<=l0;
            #1;
            if(ov!==v1 || ou!==u1 || ol!==l1 || result!==e1) $fatal(1,"RGB gain value/control mismatch: actual=%h expected=%h controls=%b%b%b/%b%b%b",result,e1,ov,ou,ol,v1,u1,l1);
            if(ov) checks=checks+1;
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(pass=0;pass<2;pass=pass+1) begin
            for(n=0;n<256;n=n+1) begin
                @(negedge clk);valid=1;user=(n==0);last=(n%16==15);
                for(lane=0;lane<4;lane=lane+1) begin
                    data[95-lane*24 -:8]=(n+lane*17)%256;
                    data[87-lane*24 -:8]=(n+lane*43)%256;
                    data[79-lane*24 -:8]=(n+lane*71)%256;
                end
                if(pass && n%7==0) begin @(negedge clk);valid=0;user=0;last=0;end
            end
            @(negedge clk);valid=0;user=0;last=0;repeat(4) @(negedge clk);
            // Reset while a valid beat remains in flight.
            @(negedge clk);valid=1;user=1;last=1;data={96{1'b1}};
            @(negedge clk);rst=0;valid=0;user=0;last=0;
            repeat(3) @(negedge clk);
            if(result!==0 || ov || ou || ol) $fatal(1,"RGB gain reset");
            rst=1;
        end
        if(checks!=512) $fatal(1,"RGB gain output count");
        $display("PASS: RGB gains all 256 values per channel/lane, saturation, gaps, two-cycle controls and reset");$finish;
    end
endmodule
