`timescale 1ns/1ps
module tb_detection_coordinates;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,sof=0;
    reg [255:0] boxes=0;
    wire [95:0] data;
    wire valid,user,last;
    integer base,slot,xx,yy,cycles;
    reg [127:0] expected,previous_digits;
    reg [63:0] r;
    detection_overlay_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_enable(1'b1),
        .I_boxes(boxes),.I_count(3'd4),.I_overflow(1'b0),.I_held(4'd0),
        .I_tdata(96'd0),.I_tvalid(1'b0),.I_tuser(sof),.I_tlast(1'b0),
        .O_tdata(data),.O_tvalid(valid),.O_tuser(user),.O_tlast(last));
    function automatic [15:0] bcd(input integer value);
        begin
            bcd[15:12]=value/1000;bcd[11:8]=(value/100)%10;
            bcd[7:4]=(value/10)%10;bcd[3:0]=value%10;
        end
    endfunction
    task start;
        begin @(negedge clk);sof=1;@(negedge clk);sof=0;boxes=0;end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=1;
        // Every horizontal pixel, every vertical pixel, odd-center rounding,
        // 999/1000 transitions and large sums, through all eight shared entries.
        for(base=0;base<1280;base=base+4) begin
            @(negedge clk);expected=0;boxes=0;previous_digits=dut.coordinates;
            for(slot=0;slot<4;slot=slot+1) begin
                xx=base+slot;yy=(base+slot)%720;r=0;r[63]=1;
                r[58:48]=xx;r[37:27]=xx+(xx<1279 ? 1 : 0);
                r[47:38]=yy;r[26:17]=yy+(yy<719 ? 1 : 0);
                boxes[slot*64 +:64]=r;
                expected[slot*32 +:16]=bcd(xx);expected[slot*32+16 +:16]=bcd(yy);
            end
            start();cycles=0;
            while(!dut.coordinates_ready && cycles<110) begin
                @(posedge clk);#1;cycles=cycles+1;
                if(!dut.coordinates_ready && dut.coordinates!==previous_digits)
                    $fatal(1,"Coordinate digits must publish atomically");
            end
            if(cycles!=104 || dut.coordinates!==expected)
                $fatal(1,"Coordinate conversion base=%0d cycles=%0d got=%h expected=%h",base,cycles,dut.coordinates,expected);
        end
        // A new SOF interrupts old conversion and restarts from new boxes.
        boxes=0;start();repeat(25) @(negedge clk);
        r=0;r[63]=1;r[58:48]=1200;r[37:27]=1279;r[47:38]=700;r[26:17]=719;
        boxes={r,r,r,r};start();repeat(105) @(negedge clk);
        if(!dut.coordinates_ready || dut.coordinates!=={4{32'h07091239}})
            $fatal(1,"Coordinate SOF restart");
        rst=0;@(negedge clk);
        if(dut.coordinates!==0 || dut.coordinates_ready) $fatal(1,"Coordinate reset");
        $display("PASS: center coordinates all 1280 X / 720 Y values, odd rounding, decimal boundaries, eight entries, 104 cycles, snapshot, atomic publication, SOF restart and reset");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Coordinates timeout");end
endmodule
