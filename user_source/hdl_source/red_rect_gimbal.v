// Visual PD velocity controller. PWM position integrates a bounded rate, while
// the rate uses frame-normalized visual velocity and observation-age prediction.
module red_rect_gimbal #(
    parameter integer FRAME_TICKS=1000000, STARTUP_FRAMES=150, STALE_FRAMES=6,
    parameter integer CENTER_X=640,CENTER_Y=360,DEAD_X=24,DEAD_Y=20,
    parameter integer RESTART_X=36,RESTART_Y=30,
    parameter integer MAX_SAMPLE_AGE=8,MAX_SAMPLE_GAP=32,LEAD_FRAMES=2,
    parameter integer KP_SHIFT=0,STEP_TICKS=250,SPEED_BOOST=1,
    parameter integer PAN_MIN=50000,PAN_MAX=100000,TILT_MIN=41667,TILT_MAX=83333,
    parameter integer CENTER_TICKS=75000,PAN_REVERSE=0,TILT_REVERSE=0
)(
    input wire I_detect_clk,I_servo_clk,I_rst_n,I_enable,I_update,I_overflow,
    input wire [255:0] I_boxes,
    input wire [3:0] I_held,
    input wire [15:0] I_frame_id,I_sample_frame_id,
    output reg O_pan_pwm,O_tilt_pwm
);
    reg locked,found;
    reg [1:0] locked_slot,slot;
    reg [63:0] box;
    reg [11:0] cx;
    reg [10:0] cy;
    integer k;
    always @(*) begin
        found=0;slot=0;box=0;
        for(k=0;k<4;k=k+1)
            if(!found && I_boxes[k*64+63] && I_boxes[k*64+61 +:2]==1 &&
                I_boxes[k*64+59 +:2]==1 && !I_held[k]) begin
                found=1;slot=k;box=I_boxes[k*64 +:64];
            end
        if(locked && I_boxes[locked_slot*64+63]) begin
            slot=locked_slot;box=I_boxes[locked_slot*64 +:64];
            found=box[62:61]==1 && box[60:59]==1 && !I_held[locked_slot];
        end
        cx=({1'b0,box[58:48]}+{1'b0,box[37:27]})>>1;
        cy=({1'b0,box[47:38]}+{1'b0,box[26:17]})>>1;
    end
    wire observation_ok=found && !I_overflow && box[58:48]<=box[37:27] &&
        box[47:38]<=box[26:17] && box[37:27]<1280 && box[26:17]<720;
    (* async_reg="true" *) reg dr1,dr2,sr1,sr2;
    always @(posedge I_detect_clk or negedge I_rst_n)
        if(!I_rst_n) begin dr1<=0;dr2<=0;end else begin dr1<=1;dr2<=dr1;end
    always @(posedge I_servo_clk or negedge I_rst_n)
        if(!I_rst_n) begin sr1<=0;sr2<=0;end else begin sr1<=1;sr2<=sr1;end
    wire pd_update,pd_valid,pd_busy;
    wire signed [8:0] pd_pan,pd_tilt;
    wire [3:0] pd_life;
    gimbal_pd_rate #(.CENTER_X(CENTER_X),.CENTER_Y(CENTER_Y),.DEAD_X(DEAD_X),.DEAD_Y(DEAD_Y),
        .RESTART_X(RESTART_X),.RESTART_Y(RESTART_Y),.MAX_SAMPLE_AGE(MAX_SAMPLE_AGE),
        .MAX_SAMPLE_GAP(MAX_SAMPLE_GAP),.LEAD_FRAMES(LEAD_FRAMES),.KP_SHIFT(KP_SHIFT),
        .RATE_LIMIT(STEP_TICKS),.PAN_REVERSE(PAN_REVERSE),.TILT_REVERSE(TILT_REVERSE)) u_pd (
        .I_clk(I_detect_clk),.I_rst_n(dr2),.I_update(I_update),.I_valid(observation_ok),
        .I_slot(slot),.I_x(cx[10:0]),.I_y(cy[9:0]),.I_frame(I_frame_id),.I_sample(I_sample_frame_id),
        .O_update(pd_update),.O_valid(pd_valid),.O_pan(pd_pan),.O_tilt(pd_tilt),.O_life(pd_life),.O_busy(pd_busy));
    // Stable bundled-data mailbox. No per-bit asynchronous coordinate sampling.
    reg [22:0] payload;
    reg req,ack;
    (* async_reg="true" *) reg ack1,ack2,req1,req2;
    always @(posedge I_detect_clk or negedge dr2) begin
        if(!dr2) begin locked<=0;locked_slot<=0;payload<=0;req<=0;ack1<=0;ack2<=0;end
        else begin
            ack1<=ack;ack2<=ack1;
            if(I_update && !pd_busy && !I_overflow) begin
                locked<=found || (locked && I_boxes[locked_slot*64+63] && I_held[locked_slot]);
                if(found) locked_slot<=slot;
            end
            if(pd_update && req==ack2) begin
                payload<={pd_valid,pd_life,pd_tilt,pd_pan};req<=~req;
            end
        end
    end
    (* async_reg="true" *) reg enable1,enable2;
    reg [1:0] enable_valid;
    reg armed;
    reg [22:0] received;
    reg [19:0] frame_count;
    reg [7:0] startup,age;
    reg [16:0] pan_ticks,tilt_ticks;
    wire frame_end=frame_count==FRAME_TICKS-1;
    wire new_command=req2!=ack;
    wire moving=armed && enable2 && startup>=STARTUP_FRAMES && received[22] &&
        age<STALE_FRAMES && age<received[21:18];
    function [16:0] apply_rate;
        input [16:0] current;
        input signed [8:0] rate;
        input integer minimum,maximum;
        reg signed [18:0] proposed;
        reg signed [10:0] base,scaled;
        begin
            base=rate;
            // Symmetric truncation: +n and -n retain equal speed magnitudes.
            scaled=SPEED_BOOST ? (base<0 ? base-((-base) >>> 1) : base+(base >>> 1)) : base;
            proposed=$signed({2'b0,current})+scaled;
            apply_rate=proposed<minimum ? minimum : proposed>maximum ? maximum : proposed[16:0];
        end
    endfunction
    always @(posedge I_servo_clk or negedge sr2) begin
        if(!sr2) begin
            req1<=0;req2<=0;ack<=0;received<=0;enable1<=0;enable2<=0;enable_valid<=0;armed<=0;
            frame_count<=FRAME_TICKS-1;startup<=0;age<=STALE_FRAMES;
            pan_ticks<=CENTER_TICKS;tilt_ticks<=CENTER_TICKS;O_pan_pwm<=0;O_tilt_pwm<=0;
        end else begin
            req1<=req;req2<=req1;enable1<=I_enable;enable2<=enable1;
            enable_valid<={enable_valid[0],1'b1};
            if(enable_valid[1] && !enable2) armed<=1;
            if(new_command) begin received<=payload;ack<=req2;age<=0;end
            else if(frame_end && age<STALE_FRAMES) age<=age+1'b1;
            if(frame_end) begin
                frame_count<=0;
                if(startup<STARTUP_FRAMES) startup<=startup+1'b1;
                // Never apply a superseded rate when a new/stop message arrives.
                if(moving && !new_command) begin
                    pan_ticks<=apply_rate(pan_ticks,$signed(received[8:0]),PAN_MIN,PAN_MAX);
                    tilt_ticks<=apply_rate(tilt_ticks,$signed(received[17:9]),TILT_MIN,TILT_MAX);
                end
                O_pan_pwm<=1;O_tilt_pwm<=1;
            end else begin
                frame_count<=frame_count+1'b1;
                O_pan_pwm<=frame_count<pan_ticks-1;O_tilt_pwm<=frame_count<tilt_ticks-1;
            end
        end
    end
endmodule

// One shared add/serial divide datapath for both axes; no parallel divider or DSP.
// rate = clamp((e + de/d(sample_frame) * (age + LEAD_FRAMES)) >>> KP_SHIFT).
// Prediction may brake to zero but cannot reverse against the observed error.
module gimbal_pd_rate #(
    parameter integer CENTER_X=640,CENTER_Y=360,DEAD_X=24,DEAD_Y=20,
    parameter integer RESTART_X=36,RESTART_Y=30,MAX_SAMPLE_AGE=8,MAX_SAMPLE_GAP=32,
    parameter integer LEAD_FRAMES=2,KP_SHIFT=0,RATE_LIMIT=250,PAN_REVERSE=0,TILT_REVERSE=0
)(
    input wire I_clk,I_rst_n,I_update,I_valid,
    input wire [1:0] I_slot,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire [15:0] I_frame,I_sample,
    output reg O_update,O_valid,
    output reg signed [8:0] O_pan,O_tilt,
    output reg [3:0] O_life,
    output wire O_busy
);
    localparam IDLE=0,PREPARE=1,MULTIPLY=2,DIVIDE=3,FINISH=4,PUBLISH=5;
    reg [2:0] state;
    reg axis,history;
    reg [1:0] previous_slot;
    reg [15:0] previous_sample;
    reg signed [12:0] previous_x,previous_y,ex,ey,dx,dy;
    reg active_x,active_y,run_x,run_y,derivative;
    reg signed [8:0] result_x,result_y;
    reg valid_result;
    reg [3:0] life,horizon,adds;
    reg [7:0] dt,divisor;
    reg [12:0] magnitude;
    reg negative;
    reg [15:0] product,dividend,quotient;
    reg [8:0] remainder;
    reg [4:0] bits_left;
    wire [15:0] sample_age=I_frame-I_sample;
    wire [15:0] sample_gap=I_sample-previous_sample;
    wire chronology=!history || (!sample_gap[15] && sample_gap!=0);
    wire acceptable=I_valid && sample_age<MAX_SAMPLE_AGE && !sample_age[15] && chronology;
    wire signed [12:0] incoming_x=$signed(CENTER_X)-$signed({1'b0,I_x});
    wire signed [12:0] incoming_y=$signed(CENTER_Y)-$signed({1'b0,I_y});
    wire same_track=history && previous_slot==I_slot;
    wire signed [12:0] difference=axis ? dy : dx;
    wire signed [12:0] error=axis ? ey : ex;
    wire running=axis ? run_y : run_x;
    wire [8:0] trial={remainder[7:0],dividend[15]};
    wire signed [17:0] predicted=$signed(error)+(negative ? -$signed({2'b0,quotient}) : $signed({2'b0,quotient}));
    wire signed [17:0] proportional=predicted >>> KP_SHIFT;
    reg signed [8:0] rate;
    always @(*) begin
        rate=0;
        if(running && ((error>0 && predicted>0) || (error<0 && predicted<0))) begin
            if(proportional>RATE_LIMIT) rate=RATE_LIMIT;
            else if(proportional< -RATE_LIMIT) rate=-RATE_LIMIT;
            else if(proportional==0) rate=predicted>0 ? 9'sd1 : -9'sd1;
            else rate=proportional[8:0];
        end
        if((axis && TILT_REVERSE) || (!axis && PAN_REVERSE)) rate=-rate;
    end
    // Conservative 60 fps source-frame lifetime converted to 50 Hz PWM periods.
    // Supported MAX_SAMPLE_AGE=1..8; leave <1 PWM period as a stop command.
    function [3:0] lifetime;
        input [15:0] remaining;
        begin case(remaining)
            0,1:lifetime=0;2:lifetime=1;3:lifetime=2;4:lifetime=3;
            5:lifetime=4;6,7:lifetime=5;default:lifetime=6;
        endcase end
    endfunction
    assign O_busy=state!=IDLE;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;axis<=0;history<=0;previous_slot<=0;previous_sample<=0;
            previous_x<=0;previous_y<=0;ex<=0;ey<=0;dx<=0;dy<=0;
            active_x<=0;active_y<=0;run_x<=0;run_y<=0;derivative<=0;
            result_x<=0;result_y<=0;valid_result<=0;life<=0;horizon<=0;adds<=0;
            dt<=1;divisor<=1;magnitude<=0;negative<=0;product<=0;dividend<=0;quotient<=0;remainder<=0;bits_left<=0;
            O_update<=0;O_valid<=0;O_pan<=0;O_tilt<=0;O_life<=0;
        end else begin
            O_update<=0;
            case(state)
                IDLE:if(I_update) begin
                    result_x<=0;result_y<=0;axis<=0;
                    valid_result<=acceptable && lifetime(MAX_SAMPLE_AGE-sample_age)!=0;
                    life<=acceptable ? lifetime(MAX_SAMPLE_AGE-sample_age) : 0;
                    if(acceptable) begin
                        ex<=incoming_x;ey<=incoming_y;
                        dx<=incoming_x-previous_x;dy<=incoming_y-previous_y;
                        derivative<=same_track && sample_gap<=MAX_SAMPLE_GAP;
                        dt<=same_track && sample_gap<=MAX_SAMPLE_GAP ? sample_gap[7:0] : 1;
                        horizon<=sample_age[3:0]+LEAD_FRAMES;
                        run_x<=incoming_x>RESTART_X || incoming_x< -RESTART_X ||
                            (same_track && active_x && (incoming_x>DEAD_X || incoming_x< -DEAD_X));
                        run_y<=incoming_y>RESTART_Y || incoming_y< -RESTART_Y ||
                            (same_track && active_y && (incoming_y>DEAD_Y || incoming_y< -DEAD_Y));
                        active_x<=incoming_x>RESTART_X || incoming_x< -RESTART_X ||
                            (same_track && active_x && (incoming_x>DEAD_X || incoming_x< -DEAD_X));
                        active_y<=incoming_y>RESTART_Y || incoming_y< -RESTART_Y ||
                            (same_track && active_y && (incoming_y>DEAD_Y || incoming_y< -DEAD_Y));
                        previous_x<=incoming_x;previous_y<=incoming_y;previous_sample<=I_sample;
                        previous_slot<=I_slot;history<=1;state<=PREPARE;
                    end else begin
                        // Bad chronology must not become a new velocity baseline.
                        if(!I_valid) begin history<=0;active_x<=0;active_y<=0;end
                        state<=PUBLISH;
                    end
                end
                PREPARE:begin
                    magnitude<=difference<0 ? -difference : difference;negative<=difference<0;
                    adds<=derivative ? horizon : 0;product<=0;quotient<=0;
                    divisor<=dt;state<=MULTIPLY;
                end
                MULTIPLY:if(adds!=0) begin product<=product+magnitude;adds<=adds-1'b1;end
                    else begin dividend<=product;quotient<=0;remainder<=0;bits_left<=16;state<=DIVIDE;end
                DIVIDE:begin
                    dividend<={dividend[14:0],1'b0};
                    quotient<={quotient[14:0],trial>={1'b0,divisor}};
                    remainder<=trial>={1'b0,divisor} ? trial-{1'b0,divisor} : trial;
                    bits_left<=bits_left-1'b1;
                    if(bits_left==1) state<=FINISH;
                end
                FINISH:begin
                    if(!axis) begin result_x<=rate;axis<=1;state<=PREPARE;end
                    else begin result_y<=rate;state<=PUBLISH;end
                end
                PUBLISH:begin
                    O_pan<=valid_result ? result_x : 0;O_tilt<=valid_result ? result_y : 0;
                    O_valid<=valid_result;O_life<=life;O_update<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule