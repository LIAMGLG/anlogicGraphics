`timescale 1ns/1ps
// Synthetic first-order servo and delayed camera: compare the previous fixed
// step/wait policy with the frame-aware damped rate controller. Not a board model.
module tb_gimbal_settle #(parameter integer DELAY=3,CADENCE=3,SPEED_BOOST=1,parameter real SERVO_ALPHA=0.5);
    reg dc=0,sc=0,rst=0,en=0,update=0;
    always #7 dc=~dc;
    always #10 sc=~sc;
    reg [255:0] boxes=0;
    reg [15:0] frame_id=0,sample=0;
    red_rect_gimbal #(.FRAME_TICKS(1000),.STARTUP_FRAMES(0),.SPEED_BOOST(SPEED_BOOST),.KP_SHIFT(5),
        .PAN_MIN(500),.PAN_MAX(1000),.TILT_MIN(500),.TILT_MAX(1000),
        .CENTER_TICKS(750),.STEP_TICKS(5),.TILT_REVERSE(1)) dut (
        .I_detect_clk(dc),.I_servo_clk(sc),.I_rst_n(rst),.I_enable(en),
        .I_update(update),.I_overflow(1'b0),.I_boxes(boxes),.I_held(4'd0),
        .I_frame_id(frame_id),.I_sample_frame_id(sample),.O_pan_pwm(),.O_tilt_pwm());
    function automatic [63:0] rect(input integer x,y);
        rect={1'b1,2'd1,2'd1,11'(x-10),10'(y-10),11'(x+10),10'(y+10),17'd100};
    endfunction
    function automatic integer abs(input integer v);return v<0 ? -v : v;endfunction
    task automatic frame;
        @(negedge sc);while(dut.frame_count!=999) @(negedge sc);@(negedge sc);
    endtask
    integer hx[0:DELAY-1],hy[0:DELAY-1],ox[0:DELAY-1],oy[0:DELAY-1],stamp[0:DELAY-1];
    real ap=750,at=750,bp=750,bt=750;
    integer oldpan=750,oldtilt=750,cdx=0,cdy=0,px,py,x,y,opx,opy;
    integer i,j,new_settle=-1,old_settle=-1,new_stable=0,old_stable=0,late_changes=0,lastp,lastt;
    integer overshoot_x=0,overshoot_y=0,noise;
    bit active_x=0,active_y=0,new_data;
    initial begin
        #31;rst=1;repeat(15) @(negedge sc);en=1;
        for(j=0;j<DELAY;j++) begin hx[j]=300;hy[j]=160;ox[j]=300;oy[j]=160;stamp[j]=0;end
        lastp=750;lastt=750;
        for(i=0;i<650;i++) begin
            frame_id=i*6/5;new_data=(i%CADENCE==0);
            px=0;py=0;
            if(new_data) begin
                @(negedge dc);boxes[63:0]=rect(hx[0],hy[0]);sample=stamp[0];update=1;
                @(negedge dc);update=0;repeat(120) @(negedge sc);
                active_x=abs(640-ox[0])>48 || (active_x && abs(640-ox[0])>24);
                active_y=abs(360-oy[0])>40 || (active_y && abs(360-oy[0])>20);
                if(cdx==0 && active_x) px=(ox[0]<640 ? 1 : -1)*(abs(640-ox[0])<=160 ? 1 : 5);
                if(cdy==0 && active_y) py=(oy[0]<360 ? -1 : 1)*(abs(360-oy[0])<=100 ? 1 : 5);
            end
            frame();
            if(px!=0) begin oldpan+=px;cdx=5;end else if(cdx>0) cdx--;
            if(py!=0) begin oldtilt+=py;cdy=5;end else if(cdy>0) cdy--;
            // First-order actuator dynamics; four source-clock frames of image age.
            ap+=(real'(dut.pan_ticks)-ap)*SERVO_ALPHA;at+=(real'(dut.tilt_ticks)-at)*SERVO_ALPHA;
            bp+=(real'(oldpan)-bp)*SERVO_ALPHA;bt+=(real'(oldtilt)-bt)*SERVO_ALPHA;
            x=$rtoi(300+2*(ap-750));y=$rtoi(160-2*(at-750));
            opx=$rtoi(300+2*(bp-750));opy=$rtoi(160-2*(bt-750));
            if(x-640>overshoot_x) overshoot_x=x-640;
            if(y-360>overshoot_y) overshoot_y=y-360;
            if(abs(x-640)<=36 && abs(y-360)<=30) new_stable++;else new_stable=0;
            if(abs(opx-640)<=36 && abs(opy-360)<=30) old_stable++;else old_stable=0;
            if(new_stable==20 && new_settle<0) new_settle=i-19;
            if(old_stable==20 && old_settle<0) old_settle=i-19;
            if(i>600 && (dut.pan_ticks!=lastp || dut.tilt_ticks!=lastt)) late_changes++;
            lastp=dut.pan_ticks;lastt=dut.tilt_ticks;
            for(j=0;j<DELAY-1;j++) begin hx[j]=hx[j+1];hy[j]=hy[j+1];ox[j]=ox[j+1];oy[j]=oy[j+1];stamp[j]=stamp[j+1];end
            noise=i>200 ? (i%2 ? 4 : -4) : 0;
            hx[DELAY-1]=x+noise;hy[DELAY-1]=y-noise;ox[DELAY-1]=opx+noise;oy[DELAY-1]=opy-noise;stamp[DELAY-1]=i*6/5;
        end
        $display("FEEDBACK: PD settle=%0d, old settle=%0d PWM frames; overshoot=%0d/%0d px, late changes=%0d, final=%0d/%0d",new_settle,old_settle,overshoot_x,overshoot_y,late_changes,x,y);
        if(new_settle<0 || old_settle<0 || new_settle*100>=old_settle*75) $fatal(1,"PD must improve example settling time by at least 25 percent");
        if(overshoot_x>36 || overshoot_y>30 || late_changes!=0) $fatal(1,"PD delayed feedback must settle without sustained hunting");
        $display("PASS: two-axis delayed first-order feedback, bounded overshoot, center noise rejection and faster convergence than fixed wait");
        $finish;
    end
    initial begin #18000000;$fatal(1,"feedback timeout");end
endmodule