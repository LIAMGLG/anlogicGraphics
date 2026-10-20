`timescale 1ns/1ps
// Real 50 MHz clock and unscaled production PWM defaults.
module tb_default_pwm;
    reg clk=0,rst=0;
    always #10 clk=~clk;
    wire pan,tilt;
    red_rect_gimbal dut (
        .I_detect_clk(clk),.I_servo_clk(clk),.I_rst_n(rst),.I_enable(1'b1),
        .I_frame_id(16'd0),.I_sample_frame_id(16'd0),.I_update(1'b0),.I_overflow(1'b0),.I_boxes(256'd0),.I_held(4'd0),
        .O_pan_pwm(pan),.O_tilt_pwm(tilt));
    time rise_at,previous_rise;
    integer i;
    initial begin
        #31;rst=1;
        previous_rise=0;
        for(i=0;i<3;i=i+1) begin
            @(posedge pan);rise_at=$time;
            if(tilt!==1) $fatal(1,"PWM axes not aligned");
            if(i>0 && rise_at-previous_rise!=20000000) $fatal(1,"default period must be 20 ms");
            previous_rise=rise_at;
            @(negedge pan);
            if($time-rise_at!=1500000 || tilt!==0) $fatal(1,"default pulse must be 1500 us");
        end
        $display("PASS: production defaults, 50 MHz, 20 ms PWM, 1500 us startup pulses");
        $finish;
    end
    initial begin #65000000;$fatal(1,"default PWM timeout");end
endmodule