`timescale 1ns/1ps
module tb_motion;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,en=0,v=0,u=0,l=0;
    reg [95:0] rgb=0;
    wire [143:0] regions;
    wire ready;
    motion_detect_rgb96 #(.IMG_WIDTH(80),.IMG_HEIGHT(80)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_enable(en),.I_tdata(rgb),
        .I_tvalid(v),.I_tuser(u),.I_tlast(l),.O_regions(regions),.O_ready(ready));
    integer f,yy,xx,k,n,expected_mean,observed;
    reg [7:0] level;
    // Independent pixel reference; varying per-lane RGB exercises both
    // horizontal pairing and all eight accumulated rows.
    function [23:0] pixel(input integer pattern,px,py);
        integer r,g,b;
        begin
            if(pattern==300) begin r=(px*7+py*3)%256;g=(px*11+py*5)%256;b=(px*13+py*17)%256; end
            else begin r=pattern;g=pattern;b=pattern; end
            pixel={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    reg [23:0] p;
    task frame(input integer pattern,rows,input bit early,gaps);
        integer y,x,lane,a,b,sum,r,g,bb;
        begin
            observed=0;
            if(early) begin
                @(negedge clk);u=1;v=0;l=0;
                @(negedge clk);u=0;
            end
            for(y=0;y<rows;y=y+1) begin
                for(x=0;x<20;x=x+1) begin
                    @(negedge clk);v=1;u=!early && y==0 && x==0;l=x==19;
                    for(lane=0;lane<4;lane=lane+1) rgb[95-lane*24 -:24]=pixel(pattern,x*4+lane,y);
                    if(en && x%2==1 && y%8==7) begin
                        sum=0;
                        for(a=y-7;a<=y;a=a+1) for(b=x*4-4;b<x*4+4;b=b+1) begin
                            p=pixel(pattern,b,a);r=p[23:16];g=p[15:8];bb=p[7:0];
                            sum=sum+(r+2*g+bb)/4;
                        end
                        expected_mean=sum/64;
                        @(posedge clk);#1;
                        if(!dut.sample || dut.total[13:6]!==expected_mean[7:0])
                            $fatal(1,"8x8 mean x=%0d y=%0d got=%0d expected=%0d",x,y,dut.total[13:6],expected_mean);
                        observed=observed+1;
                    end
                    if(gaps && x%7==0) begin
                        @(negedge clk);v=0;u=0;l=0;
                    end
                end
            end
            @(negedge clk);v=0;u=0;l=0;
            repeat(6) @(negedge clk);
            if(en && rows==80 && observed!=100) $fatal(1,"sample count %0d",observed);
        end
    endtask
    task check(input bit active);
        begin
            if(!ready || regions!==(active ? 144'd1 : 144'd0))
                $fatal(1,"motion got=%h ready=%b expected=%b",regions,ready,active);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;en=1;
        frame(40,80,0,0);check(0); // uninitialised RAM cannot alarm
        frame(100,80,1,1);check(0); // one changing frame is insufficient
        frame(40,80,0,1);check(1); // second consecutive changing frame
        frame(40,80,0,0);check(1);
        frame(40,80,1,0);check(1);
        frame(40,80,0,1);check(1);
        frame(40,80,0,0);check(0); // three-frame hold expires
        frame(56,80,0,0);check(0); // difference exactly 16 is excluded
        frame(40,80,0,0);check(0);
        frame(56,80,0,0);check(0);
        en=0;frame(220,80,0,0);
        if(ready || regions!=0) $fatal(1,"exit must clear state");
        en=1;frame(220,80,1,1);check(0); // re-entry primes reference
        frame(300,80,0,1);check(0); // independent colour mean reference
        en=0;frame(0,80,0,0);en=1;
        frame(40,40,0,0); // incomplete reference
        frame(200,80,0,0);check(0);
        frame(40,80,0,0);check(0);
        frame(200,80,0,0);check(1);
        @(negedge clk);rst=0;#1;
        if(ready || regions!=0) $fatal(1,"reset");
        $display("PASS: motion means, bubbles, early SOF, threshold, prime, stability, incomplete frame, exit/re-entry/reset");
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule

module tb_motion_720p;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,v=0,u=0,l=0;
    reg [95:0] rgb=0;
    wire [143:0] regions;
    wire ready;
    motion_detect_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_enable(en),.I_tdata(rgb),
        .I_tvalid(v),.I_tuser(u),.I_tlast(l),.O_regions(regions),.O_ready(ready));
    integer f,y,x,lane,px;
    reg [7:0] c;
    reg [143:0] expected;
    initial begin
        repeat(4) @(negedge clk);rst=1;
        expected=0;expected[50]=1;expected[143]=1;
        for(f=0;f<4;f=f+1) begin
            for(y=0;y<720;y=y+1) for(x=0;x<320;x=x+1) begin
                @(negedge clk);v=1;u=y==0 && x==0;l=x==319;
                for(lane=0;lane<4;lane=lane+1) begin
                    px=4*x+lane;c=40;
                    if(f%2 && ((px>=160 && px<240 && y>=240 && y<320) ||
                                  (px>=1200 && y>=640))) c=100;
                    rgb[95-lane*24 -:24]={c,c,c};
                end
            end
            // No blanking between frames: the pending final sample must survive SOF.
            if(f<3) begin
                @(posedge clk);#1;
            end
        end
        @(negedge clk);v=0;u=0;l=0;
        repeat(8) @(negedge clk);
        if(!ready || regions!==expected) $fatal(1,"720p map got=%h expected=%h",regions,expected);
        $display("PASS: motion 720p consecutive frames, two regions including last pixel/region");$finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule

module tb_motion_overlay;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,motion=1,ready=1,v=0,u=0,l=0;
    reg [143:0] regions=0;
    reg [95:0] data;
    wire [95:0] out;
    wire ov,ou,ol,om;
    motion_overlay_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_enable(en),.I_motion(motion),
        .I_ready(ready),.I_regions(regions),.I_tdata(data),.I_tvalid(v),.I_tuser(u),.I_tlast(l),
        .O_tdata(out),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_motion(om));
    reg [95:0] expected[0:2];
    reg [2:0] ev=0,eu=0,el=0,em=0;
    reg reference_motion=0;
    integer f,y,x,lane,px,score_x,score_y;
    reg border;
    always @(posedge clk) begin
        if(rst) begin
            expected[2]<=expected[1];expected[1]<=expected[0];
            expected[0]=data;
            if(v && f==0) for(lane=0;lane<4;lane=lane+1) begin
                px=score_x*4+lane;
                border=px<80 && score_y<64 && (px<2 || px>=78 || score_y<2);
                if(border) expected[0][95-lane*24 -:24]=24'hfff200;
            end
            if(u) reference_motion=motion;
            ev={ev[1:0],v};eu={eu[1:0],u};el={el[1:0],l};em={em[1:0],reference_motion};
            #1;
            if(ov!==ev[2] || ou!==eu[2] || ol!==el[2] || om!==em[2]) $fatal(1,"overlay control");
            if(ov && out!==expected[2]) $fatal(1,"overlay frame=%0d x=%0d y=%0d got=%h expected=%h",f,x,y,out,expected[2]);
        end
    end
    initial begin
        data={24'h123456,24'h234567,24'h345678,24'h456789};regions[0]=1;
        repeat(4) @(negedge clk);rst=1;
        for(f=0;f<3;f=f+1) begin
            en=f!=1;motion=f!=2;
            for(y=0;y<64;y=y+1) for(x=0;x<320;x=x+1) begin
                @(negedge clk);v=1;u=y==0 && x==0;l=x==319;
                score_x=x;score_y=y;
                // Changing results mid-frame must not alter latched graphics.
                if(y==4 && x==0) regions=0;
            end
            @(negedge clk);v=0;u=0;l=0;repeat(4) @(negedge clk);
        end
        $display("PASS: motion overlay lane order, frame latch, k4 disable, mode bypass and three-clock latency");$finish;
    end
endmodule
