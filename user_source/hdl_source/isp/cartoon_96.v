// Four-pixel RGB888 cartoon compositor. I_edge_data has two-cycle latency.
// Pair-average colors are posterized to 4 levels/channel. A one-row buffer
// aligns them to Sobel centers (previous row, previous two-pixel sample).
module cartoon_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720
)(
    input wire I_clk, I_rst_n, I_tlast, I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    input wire [95:0] I_edge_data,
    output wire [95:0] O_tdata
);
    localparam integer WIDTH_GROUPS = IMG_WIDTH / 4;
    (* ram_style = "auto" *) reg [11:0] color_line [0:WIDTH_GROUPS-1];
    reg [10:0] x_grp, y_pos;
    wire [10:0] current_x = I_tuser ? 11'd0 : x_grp;
    wire [10:0] current_y = I_tuser ? 11'd0 : y_pos;
    function [5:0] quantize_pair;
        input [23:0] a, b;
        reg [8:0] r_sum, g_sum, b_sum;
        begin
            r_sum = {1'b0,a[23:16]} + {1'b0,b[23:16]};
            g_sum = {1'b0,a[15:8]} + {1'b0,b[15:8]};
            b_sum = {1'b0,a[7:0]} + {1'b0,b[7:0]};
            quantize_pair = {r_sum[8:7],g_sum[8:7],b_sum[8:7]};
        end
    endfunction
    function [23:0] expand_color;
        input [5:0] c;
        begin
            expand_color = {{4{c[5:4]}},{4{c[3:2]}},{4{c[1:0]}}};
        end
    endfunction
    wire [11:0] incoming = {quantize_pair(I_tdata[95:72],I_tdata[71:48]),
                           quantize_pair(I_tdata[47:24],I_tdata[23:0])};
    // Read-before-write synchronous RAM. Keep the read register outside reset
    // so the line store can map to ERAM rather than distributed LUT memory.
    reg [11:0] middle;
    always @(posedge I_clk) begin
        if (I_rst_n && I_tvalid) begin
            middle <= color_line[current_x];
            color_line[current_x] <= incoming;
        end
    end
    reg [5:0] middle_prev;
    reg [11:0] centers_d2;
    reg valid_d1, clear_prev_d1;
    reg usable_d1, usable_d2;
    wire [23:0] color0 = expand_color(centers_d2[11:6]);
    wire [23:0] color1 = expand_color(centers_d2[5:0]);
    wire [23:0] out0 = I_edge_data[95] ? 24'd0 : color0;
    wire [23:0] out1 = I_edge_data[47] ? 24'd0 : color1;
    assign O_tdata = usable_d2 ? {out0,out0,out1,out1} : 96'd0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp <= 0; y_pos <= 0; middle_prev <= 0;
            centers_d2 <= 0; valid_d1 <= 0; clear_prev_d1 <= 0;
            usable_d1 <= 0; usable_d2 <= 0;
        end else begin
            centers_d2 <= {middle_prev,middle[11:6]};
            valid_d1 <= I_tvalid;
            clear_prev_d1 <= I_tvalid ? (I_tlast || current_x == WIDTH_GROUPS-1) : I_tuser;
            if (valid_d1) middle_prev <= middle[5:0];
            if (clear_prev_d1) middle_prev <= 0;
            usable_d1 <= I_tvalid && current_y >= 1 && current_x != 0 && !I_tuser;
            usable_d2 <= usable_d1;
            if (I_tvalid) begin
                if (I_tlast || current_x == WIDTH_GROUPS-1) begin
                    x_grp <= 0;
                    y_pos <= (current_y == IMG_HEIGHT-1) ? 11'd0 : current_y+1'b1;
                end else begin
                    x_grp <= current_x+1'b1;
                    y_pos <= current_y;
                end
            end else if (I_tuser) begin
                x_grp <= 0; y_pos <= 0;
            end
        end
    end
endmodule
