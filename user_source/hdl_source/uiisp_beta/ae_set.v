// Default-on sensor AE. Statistics are already in I_clk domain (mailbox).
// No camera/video reset, SOF gating or dependency of video startup on AE.
module ae_set #(
    parameter integer AUTO_ENABLE=1,
    parameter integer TARGET_LUMA=135,
    parameter integer CLK_HZ=23809524,
    parameter integer WARMUP_FRAMES=8, SETTLE_FRAMES=4
)(
    input wire I_clk,I_rst,
    input wire [3:0] I_btn,
    input wire I_ae_cfg_done,I_cam_cfg_done,I_iic_error,
    input wire I_stats_valid,I_high,
    input wire [7:0] I_luma,
    output reg O_ae_req,
    output reg [15:0] O_ae,O_ag,
    output reg O_adjust_toggle,
    output reg [7:0] O_target,
    output reg O_fault,
    output reg O_applied
);
    localparam integer TICK_CYCLES=CLK_HZ/5;
    localparam integer TW=$clog2(TICK_CYCLES);
    localparam integer DEBOUNCE_CYCLES=(CLK_HZ/200<2) ? 2:CLK_HZ/200;
    localparam integer DW=$clog2(DEBOUNCE_CYCLES);
    reg [TW-1:0] ticks;
    wire tick=ticks==TICK_CYCLES-1;
    (* async_reg="true" *) reg [1:0] btn1,btn2;
    reg [1:0] candidate,stable;
    reg [DW-1:0] debounce;
    wire key_commit=debounce==DEBOUNCE_CYCLES-1 && candidate==btn2 && candidate!=stable;
    wire minus=(key_commit && stable[0] && !candidate[0]) || (tick && !stable[0]);
    wire plus=(key_commit && stable[1] && !candidate[1]) || (tick && !stable[1]);
    reg [3:0] warmup,cooldown;
    reg waiting,saw_busy,initialized;
    reg [2:0] wait_ticks;
    reg [15:0] manual_gain;
    reg [15:0] next_ae,next_ag;
    wire [8:0] luma={1'b0,I_luma},target={1'b0,O_target};
    wire down=luma>target+9'd8 || (I_high && luma>=target-9'd8);
    wire up=luma+9'd8<target && !I_high;
    wire far_error=luma>target+9'd32 || luma+9'd32<target;
    wire [15:0] fractional_step=far_error ? (O_ae>>2):(O_ae>>4);
    wire [15:0] exposure_step=fractional_step<2 ? 16'd2:fractional_step;
    wire [15:0] gain_step=far_error ? 16'd4:16'd1;
    always @(*) begin
        next_ae=O_ae;next_ag=O_ag;
        if(down) begin
            if(O_ag>16) next_ag=(O_ag>16+gain_step) ? O_ag-gain_step:16'd16;
            else next_ae=(O_ae>2+exposure_step) ? O_ae-exposure_step:16'd2;
        end else if(up) begin
            if(O_ae<1991) next_ae=(O_ae<1991-exposure_step) ? O_ae+exposure_step:16'd1991;
            else next_ag=(O_ag<176-gain_step) ? O_ag+gain_step:16'd176;
        end
    end
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            ticks<=0;btn1<=2'b11;btn2<=2'b11;candidate<=2'b11;stable<=2'b11;debounce<=0;
            warmup<=0;cooldown<=0;waiting<=0;saw_busy<=0;initialized<=0;wait_ticks<=0;
            O_ae_req<=0;O_ae<=1991;O_ag<=16;manual_gain<=144;
            O_target<=TARGET_LUMA;O_adjust_toggle<=0;O_fault<=0;O_applied<=0;
        end else begin
            btn1<=I_btn[3:2];btn2<=btn1;
            if(btn2!=candidate) begin candidate<=btn2;debounce<=0;end
            else if(debounce!=DEBOUNCE_CYCLES-1) debounce<=debounce+1'b1;
            else stable<=candidate;
            ticks<=tick ? 0:ticks+1'b1;
            O_ae_req<=0;
            O_applied<=0;
            if(minus) begin
                if(AUTO_ENABLE!=0) begin if(O_target>=100) O_target<=O_target-5;end
                else if(manual_gain>16) manual_gain<=manual_gain-1'b1;
            end else if(plus) begin
                if(AUTO_ENABLE!=0) begin if(O_target<=210) O_target<=O_target+5;end
                else if(manual_gain<176) manual_gain<=manual_gain+1'b1;
            end
            if(I_iic_error) O_fault<=1;
            if(waiting) begin
                if(!I_ae_cfg_done) saw_busy<=1;
                if(saw_busy && I_ae_cfg_done) begin
                    waiting<=0;saw_busy<=0;cooldown<=SETTLE_FRAMES;wait_ticks<=0;
                    if(!O_fault && !I_iic_error) O_applied<=1;
                end else if(tick) begin
                    if(wait_ticks==5) begin O_fault<=1;waiting<=0;end
                    else wait_ticks<=wait_ticks+1'b1;
                end
            end else if(!O_fault && !I_iic_error && I_cam_cfg_done && I_ae_cfg_done) begin
                if(AUTO_ENABLE!=0) begin
                    if(I_stats_valid) begin
                        if(warmup<WARMUP_FRAMES) warmup<=warmup+1'b1;
                        else if(cooldown!=0) cooldown<=cooldown-1'b1;
                        else if(!initialized || next_ae!=O_ae || next_ag!=O_ag) begin
                            O_ae<=next_ae;O_ag<=next_ag;initialized<=1;
                            O_ae_req<=1;waiting<=1;saw_busy<=0;wait_ticks<=0;
                            O_adjust_toggle<=~O_adjust_toggle;
                        end
                    end
                end else if(!initialized || O_ag!=manual_gain) begin
                    O_ae<=1991;O_ag<=manual_gain;initialized<=1;
                    O_ae_req<=1;waiting<=1;saw_busy<=0;wait_ticks<=0;
                    O_adjust_toggle<=~O_adjust_toggle;
                end
            end
        end
    end
endmodule

// Display written setpoints, not sensor readback or optical measurements.
// At nominal 720p60/VTS1000 one half-line is 1/120 ms, so rounded 0.1ms
// exposure is (AE+6)/12. Gain follows SC520GainTbl's coarse/fine mapping.
// Slow serial arithmetic is outside the video path; one font converter is
// shared by the two numbers. The producer is >=4 frames apart (>200 clocks).
module ae_display_status(
    input wire I_clk,I_rst_n,I_applied,I_fault,
    input wire [10:0] I_ae,
    input wire [7:0] I_ag,
    output wire [29:0] O_status
);
    reg [1:0] state;
    reg [11:0] remainder,binary;
    reg [7:0] tenths;
    reg [16:0] gain_work;
    reg [2:0] shifts;
    reg [3:0] bits_left;
    reg [15:0] decimal,adjusted;
    reg [11:0] pending_exposure;
    reg [27:0] digits;
    reg ready;
    wire [7:0] step=I_ag<=16 ? 8'd0 : (I_ag>=176 ? 8'd160:I_ag-8'd16);
    wire [12:0] mantissa={7'd0,1'b1,step[4:0]};
    wire [15:0] shifted={adjusted[14:0],binary[11]};
    integer digit;
    assign O_status={I_fault,ready,digits};
    always @(*) begin
        adjusted=decimal;
        for(digit=0;digit<4;digit=digit+1)
            if(decimal[digit*4 +:4]>=5) adjusted[digit*4 +:4]=decimal[digit*4 +:4]+4'd3;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=0;remainder<=0;binary<=0;tenths<=0;gain_work<=0;shifts<=0;
            bits_left<=0;decimal<=0;pending_exposure<=0;digits<=0;ready<=0;
        end else case(state)
            0: if(I_applied) begin
                remainder<={1'b0,I_ae}+12'd6;tenths<=0;
                gain_work<=(mantissa<<6)+(mantissa<<5)+(mantissa<<2);
                shifts<=step[7:5];state<=1;
            end
            1: if(remainder>=12) begin remainder<=remainder-12'd12;tenths<=tenths+1'b1;end
               else if(shifts!=0) begin gain_work<=gain_work<<1;shifts<=shifts-1'b1;end
               else begin binary<={4'd0,tenths};decimal<=0;bits_left<=11;state<=2;end
            2: begin
                binary<=binary<<1;decimal<=shifted;
                if(bits_left==0) begin
                    pending_exposure<=shifted[11:0];binary<=gain_work[16:5]+gain_work[4];
                    decimal<=0;bits_left<=11;state<=3;
                end else bits_left<=bits_left-1'b1;
            end
            3: begin
                binary<=binary<<1;decimal<=shifted;
                if(bits_left==0) begin digits<={pending_exposure,shifted};ready<=1;state<=0;end
                else bits_left<=bits_left-1'b1;
            end
        endcase
    end
endmodule
