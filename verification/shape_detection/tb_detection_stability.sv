`timescale 1ns/1ps
module tb_detection_stability;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,update=0,overflow=0;
    reg [255:0] boxes=0;
    reg [2:0] count=0;
    wire [255:0] result;
    wire [2:0] result_count;
    wire result_overflow,done;
    detection_result_stabilizer dut(.I_clk(clk),.I_rst_n(rst),.I_update(update),.I_overflow(overflow),
        .I_boxes(boxes),.I_count(count),.O_boxes(result),.O_count(result_count),.O_overflow(result_overflow),.O_update(done));
    function automatic [63:0] record(input integer x,input integer color,input integer shape);
        reg [63:0] r;
        begin
            r=0;r[63]=1;r[62:61]=color;r[60:59]=shape;
            r[58:48]=x;r[37:27]=x+40;r[47:38]=100;r[26:17]=140;r[16:0]=100;
            record=r;
        end
    endfunction
    task submit(input reg [255:0] value,input integer n,input bit ov,input reg [255:0] expected);
        integer waits;
        begin
            @(negedge clk);boxes=value;count=n;overflow=ov;update=1;
            @(negedge clk);update=0;waits=0;
            while(!done && waits<100) begin @(posedge clk);#1;waits=waits+1;end
            if(!done || result!==expected || result_count!=(ov ? 0:n) || result_overflow!==ov)
                $fatal(1,"Stable association got %h expected %h",result,expected);
            repeat(2) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        submit(record(100,1,1),1,0,record(100,1,1));
        submit(record(101,1,2),1,0,record(101,1,1));
        submit(record(102,1,0),1,0,record(102,1,1));
        submit(record(103,1,1),1,0,record(103,1,1));
        submit(record(104,1,3),1,0,record(104,1,1));
        submit(record(105,1,3),1,0,record(105,1,1));
        submit(record(106,1,3),1,0,record(106,1,3));
        // Same-color target at another location gets its own cold classification.
        submit({128'd0,record(300,1,2),record(107,1,3)},2,0,{128'd0,record(300,1,2),record(107,1,3)});
        // Rank order changes, while identity and pending history follow position.
        submit({128'd0,record(108,1,2),record(301,1,1)},2,0,{128'd0,record(108,1,3),record(301,1,2)});
        submit({128'd0,record(109,1,2),record(302,1,1)},2,0,{128'd0,record(109,1,3),record(302,1,2)});
        submit({128'd0,record(110,1,2),record(303,1,1)},2,0,{128'd0,record(110,1,2),record(303,1,1)});
        // Repeated UNKNOWN eventually clears a stale confident class.
        submit(record(304,1,0),1,0,record(304,1,1));
        submit(record(305,1,0),1,0,record(305,1,1));
        submit(record(306,1,0),1,0,record(306,1,0));
        submit(0,0,0,0);submit(record(306,1,2),1,0,record(306,1,2));
        submit(record(306,1,2),1,1,0);submit(record(306,1,3),1,0,record(306,1,3));
        @(negedge clk);rst=0;@(negedge clk);
        if(result!==0 || result_count!==0 || done) $fatal(1,"Stabilizer reset");
        $display("PASS: stability, pending reset, three-update commit, movement, same-color association, ranking, UNKNOWN expiry, removal, overflow, reset");
        $finish;
    end
endmodule
