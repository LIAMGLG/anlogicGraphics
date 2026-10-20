`timescale 1ns/1ps
// Position/rate arithmetic with production pulse counts and shortened frame
// time. This test does not claim valid PWM duty cycles at the shortened period;
// tb_default_pwm separately checks the real 50 MHz / 20 ms waveform.
module tb_gimbal_limits;
    reg dc=0,sc=0,rst=0,en=0,update=0;
    always #7 dc=~dc;
    always #10 sc=~sc;
    reg [255:0] boxes=0;
    reg [15:0] sample=0,frame_id=1;
    red_rect_gimbal #(.FRAME_TICKS(1000),.STARTUP_FRAMES(0),.TILT_REVERSE(1)) dut(
        .I_detect_clk(dc),.I_servo_clk(sc),.I_rst_n(rst),.I_enable(en),
        .I_update(update),.I_overflow(1'b0),.I_boxes(boxes),.I_held(4'd0),
        .I_frame_id(frame_id),.I_sample_frame_id(sample),.O_pan_pwm(),.O_tilt_pwm());
    function automatic [63:0] rect(input integer x,y);
        rect={1'b1,2'd1,2'd1,11'(x-10),10'(y-10),11'(x+10),10'(y+10),17'd100};
    endfunction
    function automatic integer abs(input integer value);return value<0 ? -value : value;endfunction
    task automatic step(input integer x,y);
        integer op,ot;
        @(negedge dc);sample++;frame_id=sample+1;boxes[63:0]=rect(x,y);update=1;
        @(negedge dc);update=0;repeat(120) @(negedge sc);
        op=dut.pan_ticks;ot=dut.tilt_ticks;
        while(dut.frame_count!=999) @(negedge sc);
        @(negedge sc);
        if(abs(int'(dut.pan_ticks)-op)>375 || abs(int'(dut.tilt_ticks)-ot)>375)
            $fatal(1,"boosted velocity exceeded 375 ticks per PWM period");
        if(dut.pan_ticks<50000 || dut.pan_ticks>100000 || dut.tilt_ticks<41667 || dut.tilt_ticks>83333)
            $fatal(1,"production mechanical pulse limits");
    endtask
    integer i;
    initial begin
        #31;rst=1;repeat(15) @(negedge sc);en=1;
        step(300,80);
        if(dut.pan_ticks!=75375 || dut.tilt_ticks!=74625) $fatal(1,"50 percent boost must be symmetric");
        repeat(120) step(300,80);
        if(dut.pan_ticks!=100000 || dut.tilt_ticks!=41667) $fatal(1,"pan left / head-up 60 degree limit");
        repeat(150) step(980,640);
        if(dut.pan_ticks!=50000 || dut.tilt_ticks!=83333) $fatal(1,"pan right / head-down 15 degree limit");
        // Also verify the small signed rates do not acquire a directional bias.
        if(dut.apply_rate(75000,9'sd1,41667,83333)!=75001 ||
            dut.apply_rate(75000,-9'sd1,41667,83333)!=74999 ||
            dut.apply_rate(75000,9'sd3,41667,83333)!=75004 ||
            dut.apply_rate(75000,-9'sd3,41667,83333)!=74996)
            $fatal(1,"symmetric half-rate truncation");
        $display("PASS: production head-up 60 / head-down 15 limits, 1.5x symmetric rate and boosted slew cap");
        $finish;
    end
    initial begin #8000000;$fatal(1,"production limit timeout");end
endmodule