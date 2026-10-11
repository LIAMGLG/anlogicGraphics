`timescale 1ns/1ps
module tb_latency_full_frame;
    reg clk=0,rst=0,mv=0,ws=0,commit=0,rs=0;
    always #5 clk=~clk;
    reg [24:0] addr=0;
    wire pub,bad,error;wire [64:0] meta;
    latency_slots dut(.I_clk(clk),.I_rst_n(rst),.I_meta_valid(mv),
        .I_meta({1'b1,32'd42,32'd1000}),.I_write_start(ws),.I_write_slot(2'd2),
        .I_commit(commit),.I_commit_addr(addr),.I_read_start(rs),.I_read_slot(2'd2),
        .O_publish(pub),.O_read_meta(meta),.O_read_bad(bad),.O_error(error));
    initial begin
        #23;rst=1;
        @(negedge clk);mv=1;ws=1;@(negedge clk);mv=0;ws=0;
        repeat(3) @(negedge clk);
        commit=1;
        for(integer w=0;w<172799;w=w+1) begin
            addr=14000000+w*8;@(negedge clk);
        end
        commit=0;rs=1;@(posedge clk);#1;
        if(meta[64] || !bad) $fatal(1,"frame marked complete one word too early");
        @(negedge clk);rs=0;commit=1;addr=14000000+172799*8;
        @(negedge clk);commit=0;rs=1;@(posedge clk);#1;
        if(!meta[64] || bad || meta[63:32]!=42 || error) $fatal(1,"real 720p frame completion mismatch");
        @(negedge clk);rs=0;commit=1;addr=14000000+172799*8;
        @(posedge clk);#1;
        if(!error) $fatal(1,"duplicated DDR word not rejected");
        $display("PASS: real 1280x720 frame requires all 172800 ordered 128-bit memory writes");
        $finish;
    end
    initial begin #3000000;$fatal(1,"full frame timeout");end
endmodule
