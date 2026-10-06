module edge_detect_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter EDGE_TH    = 11'd80,
    parameter integer DYNAMIC_THRESHOLD = 0
)(
    input               I_clk,
    input               I_rst_n,
    input      [10:0]   I_edge_th,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input               O_tready,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [95:0]   O_tdata,
    output reg          O_tvalid,
    output              I_tready
);

assign I_tready = O_tready;

wire [23:0] pix0 = I_tdata[95:72];
wire [23:0] pix1 = I_tdata[71:48];
wire [23:0] pix2 = I_tdata[47:24];
wire [23:0] pix3 = I_tdata[23:0];

// Low-cost luminance approximation: R/4 + G/2 + B/4.  Its maximum is
// 253, so it cannot overflow an 8-bit result and requires no divider.
wire [7:0] gray0 = {2'b0,pix0[23:18]} + {1'b0,pix0[15:9]} + {2'b0,pix0[7:2]};
wire [7:0] gray1 = {2'b0,pix1[23:18]} + {1'b0,pix1[15:9]} + {2'b0,pix1[7:2]};
wire [7:0] gray2 = {2'b0,pix2[23:18]} + {1'b0,pix2[15:9]} + {2'b0,pix2[7:2]};
wire [7:0] gray3 = {2'b0,pix3[23:18]} + {1'b0,pix3[15:9]} + {2'b0,pix3[7:2]};

localparam IMG_WIDTH_GRP = (IMG_WIDTH >> 2);

// Use two grayscale samples per 4-pixel input beat.  Each sample represents
// a neighbouring pair of pixels, providing 640 horizontal edge samples while
// keeping the two line buffers small enough for this device.
wire [8:0] pair_sum0 = {1'b0,gray0} + {1'b0,gray1};
wire [8:0] pair_sum1 = {1'b0,gray2} + {1'b0,gray3};
wire [7:0] pair0 = pair_sum0[8:1];
wire [7:0] pair1 = pair_sum1[8:1];

(* ram_style = "auto" *) reg [15:0] line1_mem [0:IMG_WIDTH_GRP-1];
(* ram_style = "auto" *) reg [15:0] line2_mem [0:IMG_WIDTH_GRP-1];

reg [10:0] x_grp;
reg [10:0] y_pos;

// Frame start can accompany the first pixel beat or precede valid data.
wire [10:0] current_x = I_tuser ? 11'd0 : x_grp;
wire [10:0] current_y = I_tuser ? 11'd0 : y_pos;
wire [15:0] top_word = line2_mem[current_x];
wire [15:0] mid_word = line1_mem[current_x];
wire [15:0] bot_word = {pair0,pair1};

wire [7:0] top0 = top_word[15:8];
wire [7:0] top1 = top_word[7:0];
wire [7:0] mid0 = mid_word[15:8];
wire [7:0] mid1 = mid_word[7:0];

reg [7:0] top_prev2, top_prev1;
reg [7:0] mid_prev2, mid_prev1;
reg [7:0] bot_prev2, bot_prev1;

function [25:0] sobel_gradient;
    input [7:0] a00, a01, a02;
    input [7:0] a10, a11, a12;
    input [7:0] a20, a21, a22;
    reg signed [12:0] gx_f;
    reg signed [12:0] gy_f;
    begin
        gx_f = -$signed({1'b0,a00}) + $signed({1'b0,a02})
             - ($signed({1'b0,a10}) <<< 1) + ($signed({1'b0,a12}) <<< 1)
             - $signed({1'b0,a20}) + $signed({1'b0,a22});
        gy_f =  $signed({1'b0,a00}) + ($signed({1'b0,a01}) <<< 1) + $signed({1'b0,a02})
             - $signed({1'b0,a20}) - ($signed({1'b0,a21}) <<< 1) - $signed({1'b0,a22});
        sobel_gradient = {gx_f, gy_f};
    end
endfunction

// Two Sobel windows are evaluated per input beat. Each result is duplicated
// to its corresponding pair of output pixels.
wire [25:0] gradient0 = sobel_gradient(top_prev2,top_prev1,top0,
                             mid_prev2,mid_prev1,mid0,
                             bot_prev2,bot_prev1,pair0);
wire [25:0] gradient1 = sobel_gradient(top_prev1,top0,top1,
                             mid_prev1,mid0,mid1,
                             bot_prev1,pair0,pair1);

wire window_valid = (current_y >= 11'd2) && (current_x != 11'd0) && !I_tuser;
// Register gradients before absolute values, sum and threshold to keep
// the two-pixel Sobel calculation within the camera clock period.
reg [25:0] gradient0_d1, gradient1_d1;
wire [10:0] threshold_value = DYNAMIC_THRESHOLD ? I_edge_th : EDGE_TH;
reg [10:0] threshold_d1;
reg window_valid_d1, last_d1, user_d1, valid_d1;
wire [12:0] abs_gx0 = gradient0_d1[25] ? -gradient0_d1[25:13] : gradient0_d1[25:13];
wire [12:0] abs_gy0 = gradient0_d1[12] ? -gradient0_d1[12:0] : gradient0_d1[12:0];
wire [12:0] abs_gx1 = gradient1_d1[25] ? -gradient1_d1[25:13] : gradient1_d1[25:13];
wire [12:0] abs_gy1 = gradient1_d1[12] ? -gradient1_d1[12:0] : gradient1_d1[12:0];
wire [13:0] mag0 = {1'b0,abs_gx0} + {1'b0,abs_gy0};
wire [13:0] mag1 = {1'b0,abs_gx1} + {1'b0,abs_gy1};
wire edge0 = window_valid_d1 && (mag0 >= threshold_d1);
wire edge1 = window_valid_d1 && (mag1 >= threshold_d1);

wire [23:0] out0 = edge0 ? 24'hffffff : 24'h000000;
wire [23:0] out1 = edge1 ? 24'hffffff : 24'h000000;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        threshold_d1 <= EDGE_TH;
        gradient0_d1 <= 26'd0; gradient1_d1 <= 26'd0;
        window_valid_d1 <= 1'b0;
        last_d1 <= 1'b0; user_d1 <= 1'b0; valid_d1 <= 1'b0;
        O_tlast <= 1'b0; O_tuser <= 1'b0; O_tvalid <= 1'b0;
        O_tdata <= 96'd0;
        x_grp <= 11'd0; y_pos <= 11'd0;
        top_prev2 <= 8'd0; top_prev1 <= 8'd0;
        mid_prev2 <= 8'd0; mid_prev1 <= 8'd0;
        bot_prev2 <= 8'd0; bot_prev1 <= 8'd0;
        // No memory reset: the first two masked rows initialize both buffers.
    end else begin
        threshold_d1 <= threshold_value;
        gradient0_d1 <= gradient0;
        gradient1_d1 <= gradient1;
        window_valid_d1 <= window_valid;
        last_d1 <= I_tlast; user_d1 <= I_tuser; valid_d1 <= I_tvalid;
        O_tlast <= last_d1; O_tuser <= user_d1; O_tvalid <= valid_d1;
        O_tdata <= valid_d1 ? {out0,out0,out1,out1} : 96'd0;

        if(I_tvalid) begin
            line2_mem[current_x] <= mid_word;
            line1_mem[current_x] <= bot_word;
            top_prev2 <= top0; top_prev1 <= top1;
            mid_prev2 <= mid0; mid_prev1 <= mid1;
            bot_prev2 <= pair0; bot_prev1 <= pair1;

            if(I_tlast || current_x == IMG_WIDTH_GRP - 1) begin
                x_grp <= 11'd0;
                y_pos <= (current_y == IMG_HEIGHT - 1) ? 11'd0 : current_y + 1'b1;
                top_prev2 <= 8'd0; top_prev1 <= 8'd0;
                mid_prev2 <= 8'd0; mid_prev1 <= 8'd0;
                bot_prev2 <= 8'd0; bot_prev1 <= 8'd0;
            end else begin
                x_grp <= current_x + 1'b1;
                y_pos <= current_y;
            end
        end else if(I_tuser) begin
            x_grp <= 11'd0; y_pos <= 11'd0;
            top_prev2 <= 8'd0; top_prev1 <= 8'd0;
            mid_prev2 <= 8'd0; mid_prev1 <= 8'd0;
            bot_prev2 <= 8'd0; bot_prev1 <= 8'd0;
        end
    end
end

endmodule
