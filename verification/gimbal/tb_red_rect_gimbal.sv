`timescale 1ns/1ps
module tb_red_rect_gimbal;
    reg dc=0,sc=0,rst=0,en=1,update=0,overflow=0;
    always #7 dc=~dc;
    always #10 sc=~sc;
    reg [255:0] boxes=0;
    reg [3:0] held=0;
    reg [15:0] sample=0,frame_id=2;
    wire pan,tilt;
    red_rect_gimbal #(.FRAME_TICKS(1000),.STARTUP_FRAMES(3),.SPEED_BOOST(0),.KP_SHIFT(6),
        .PAN_MIN(50),.PAN_MAX(100),.TILT_MIN(60),.TILT_MAX(110),
        .CENTER_TICKS(75),.STEP_TICKS(2),.TILT_REVERSE(1)) dut (
        .I_detect_clk(dc),.I_servo_clk(sc),.I_rst_n(rst),.I_enable(en),
        .I_update(update),.I_overflow(overflow),.I_boxes(boxes),.I_held(held),
        .I_frame_id(frame_id),.I_sample_frame_id(sample),.O_pan_pwm(pan),.O_tilt_pwm(tilt));
    function automatic [63:0] rect(input integer x,y,color=1,shape=1);
        rect={1'b1,2'(color),2'(shape),11'(x-20),10'(y-20),11'(x+20),10'(y+20),17'd100};
    endfunction
    task automatic check(input bit ok,input string msg);
        if(!ok) $fatal(1,"%s",msg);
    endtask
    task automatic send;
        @(negedge dc);sample++;frame_id=sample+2;update=1;
        @(negedge dc);update=0;
        repeat(120) @(negedge sc);
    endtask
    task automatic frame;
        @(negedge sc);
        while(dut.frame_count!=999) @(negedge sc);
        @(negedge sc);
    endtask
    integer cycle=0,ps=-1,ts=-1,pp=-1,tp=-1,pw,tw;
    reg prev_pan=0,prev_tilt=0;
    always @(negedge sc) begin
        if(!rst || !dut.sr2) begin cycle=0;ps=-1;ts=-1;pp=-1;tp=-1;prev_pan=0;prev_tilt=0;end
        else begin
            cycle++;
            if(pan && !prev_pan) begin
                if(pp>=0) check(cycle-pp==1000,"PWM pan period");
                pp=cycle;ps=cycle;pw=dut.pan_ticks;
            end
            if(!pan && prev_pan) check(cycle-ps==pw,"PWM pan width");
            if(tilt && !prev_tilt) begin
                if(tp>=0) check(cycle-tp==1000,"PWM tilt period");
                tp=cycle;ts=cycle;tw=dut.tilt_ticks;
            end
            if(!tilt && prev_tilt) check(cycle-ts==tw,"PWM tilt width");
            prev_pan=pan;prev_tilt=tilt;
        end
    end
    integer p,t,i;
    initial begin
        #31;rst=1;boxes[63:0]=rect(400,200);
        repeat(5) begin send();frame();check(dut.pan_ticks==75 && dut.tilt_ticks==75 && !dut.armed,"boot ON interlock");end
        en=0;repeat(8) @(negedge sc);en=1;
        send();frame();check(dut.pan_ticks==77 && dut.tilt_ticks==73,"PD pan/actual reversed tilt direction");
        boxes[127:64]=rect(900,500);send();
        check($signed(dut.received[8:0])==2,"fixed target ID");
        held=1;send();p=dut.pan_ticks;t=dut.tilt_ticks;frame();
        check(!dut.received[22] && dut.pan_ticks==p && dut.tilt_ticks==t,"held slot stops instead of switching");
        boxes[63:0]=0;held=0;send();frame();
        check(dut.pan_ticks==p-2 && dut.tilt_ticks==t+2,"reacquire other target and reverse tilt");
        boxes[127:64]=rect(640,360);send();p=dut.pan_ticks;t=dut.tilt_ticks;repeat(3) frame();
        check(dut.pan_ticks==p && dut.tilt_ticks==t,"center stop");
        boxes[127:64]=rect(610,335);send();frame();check(dut.pan_ticks==p && dut.tilt_ticks==t,"hysteresis");
        boxes[127:64]=rect(400,200,2,1);send();check(!dut.received[22],"green ignored");
        boxes[127:64]=rect(400,200,1,2);send();check(!dut.received[22],"circle ignored");
        boxes[127:64]=rect(400,200);overflow=1;send();check(!dut.received[22],"overflow stop");overflow=0;
        for(i=0;i<35;i++) begin
            send();p=dut.pan_ticks;t=dut.tilt_ticks;frame();
            check(dut.pan_ticks-p>=0 && dut.pan_ticks-p<=2,"pan slew");
            check(t-dut.tilt_ticks>=0 && t-dut.tilt_ticks<=2,"tilt slew");
        end
        check(dut.pan_ticks==100 && dut.tilt_ticks==60,"first limits");
        boxes[127:64]=rect(900,500);
        repeat(35) begin send();frame();end
        check(dut.pan_ticks==50 && dut.tilt_ticks==110,"opposite limits");
        boxes[127:64]=rect(400,200);en=0;send();p=dut.pan_ticks;frame();check(dut.pan_ticks==p,"disable holds");
        en=1;send();frame();check(dut.pan_ticks>p,"enable resumes");
        repeat(8) frame();p=dut.pan_ticks;t=dut.tilt_ticks;repeat(4) frame();
        check(dut.pan_ticks==p && dut.tilt_ticks==t,"rate expires without new source observations");
        #3;rst=0;#1;check(!pan && !tilt,"async PWM reset");#27;rst=1;
        repeat(5) begin send();frame();end
        check(dut.pan_ticks==75 && dut.tilt_ticks==75 && !dut.armed,"reset rearming");
        rst=0;en=0;#27;rst=1;repeat(5) begin send();frame();end
        check(dut.armed && dut.pan_ticks==75,"boot OFF arms without movement");
        en=1;send();frame();check(dut.pan_ticks>75 && dut.tilt_ticks<75,"manual start after OFF boot");
        $display("PASS: PD gimbal CDC, boot arming, target identity, held/loss, filters, reversal, limits, slew, expiry, reset and exact PWM");
        $finish;
    end
    initial begin #6000000;$fatal(1,"gimbal timeout");end
endmodule