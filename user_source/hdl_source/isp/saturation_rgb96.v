// Display-only saturation S=5/4. Approximate luma Y=(R+2G+B)/4.
// Four RGB888 pixels per beat; data, mode and controls delayed two clocks.
module saturation_rgb96 (
    input wire I_clk,I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    input wire [1:0] I_mode,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast,
    output reg [1:0] O_mode
);
    reg [95:0] rgb_d;
    reg [9:0] luma_sum[0:3];
    reg valid_d,user_d,last_d;
    reg [1:0] mode_d;
    integer lane;
    function [7:0] adjust;
        input [7:0] channel,luma;
        reg signed [11:0] scaled;
        begin
            // (5*C-Y)/4 = Y + 1.25*(C-Y), floor, then clip.
            scaled=($signed({4'b0,channel}) <<< 2)+$signed({4'b0,channel})-$signed({4'b0,luma});
            if(scaled<0) adjust=8'd0;
            else if(scaled>=12'sd1020) adjust=8'd255;
            else adjust=scaled[9:2];
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            rgb_d<=0;valid_d<=0;user_d<=0;last_d<=0;mode_d<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_mode<=0;
            for(lane=0;lane<4;lane=lane+1) luma_sum[lane]<=0;
        end else begin
            rgb_d<=I_tdata;
            for(lane=0;lane<4;lane=lane+1) begin
                luma_sum[lane]<={2'b0,I_tdata[95-lane*24 -:8]}+
                    {1'b0,I_tdata[87-lane*24 -:8],1'b0}+{2'b0,I_tdata[79-lane*24 -:8]};
                O_tdata[95-lane*24 -:24]<={
                    adjust(rgb_d[95-lane*24 -:8],luma_sum[lane][9:2]),
                    adjust(rgb_d[87-lane*24 -:8],luma_sum[lane][9:2]),
                    adjust(rgb_d[79-lane*24 -:8],luma_sum[lane][9:2])};
            end
            valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tlast;mode_d<=I_mode;
            O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;O_mode<=mode_d;
        end
    end
endmodule
