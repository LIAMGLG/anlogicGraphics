// Four-pixel RGB888 mode label, using the reference lab_ex3_osd character ROM.
// Pixel 0 occupies [95:72], matching data128_96 and the video packer.
// Fixed panel: x=16..239, y=16..47; 16x16 glyphs enlarged 2x.
// Adds one cycle to data and all stream control signals. No independent stall buffer.
module mode_osd_rgb96 #(
    parameter integer IMG_WIDTH = 1280
)(
    input wire I_clk, I_rst_n,
    input wire [2:0] I_mode,
    input wire [95:0] I_tdata,
    input wire I_tvalid, I_tuser, I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid, O_tuser, O_tlast
);
    reg [11:0] x;
    reg [10:0] y;
    wire [11:0] current_x = I_tuser ? 12'd0 : x;
    wire [10:0] current_y = I_tuser ? 11'd0 : y;
    wire [11:0] local_x = current_x - 12'd16;
    wire [10:0] local_y = current_y - 11'd16;
    wire inside_panel = current_x >= 16 && current_x < 240 &&
                        current_y >= 16 && current_y < 48;
    wire [2:0] mode=I_mode<=4 ? I_mode : 3'd0;
    reg [7:0] character;
    wire [15:0] glyph;
    reg [95:0] rendered;
    integer lane;
    reg [3:0] column;

    always @(*) begin
        character = 8'h20;
        if (inside_panel) case({mode,local_x[7:5]})
            6'd0:character="N";
            6'd1:character="O";
            6'd2:character="R";
            6'd3:character="M";
            6'd4:character="A";
            6'd5:character="L";
            6'd8:character="B";
            6'd9:character="I";
            6'd10:character="N";
            6'd11:character="A";
            6'd12:character="R";
            6'd13:character="Y";
            6'd16:character="S";
            6'd17:character="O";
            6'd18:character="B";
            6'd19:character="E";
            6'd20:character="L";
            6'd24:character="C";
            6'd25:character="A";
            6'd26:character="R";
            6'd27:character="T";
            6'd28:character="O";
            6'd29:character="O";
            6'd30:character="N";
            6'd32:character="G";
            6'd33:character="R";
            6'd34:character="A";
            6'd35:character="Y";
            default:character=8'h20;
        endcase
    end
    osd_char_lib u_font (.I_char(character), .I_row(local_y[4:1]), .O_row_bits(glyph));

    // Panel origin, character pitch and input groups are all four-pixel aligned,
    // so a single character row serves all four lanes.
    always @(*) begin
        rendered = I_tdata;
        column = 0;
        for (lane=0; lane<4; lane=lane+1) begin
            column = (local_x[4:0] + lane) >> 1;
            if (inside_panel)
                rendered[95-lane*24 -: 24] = glyph[15-column] ? 24'hfff200 : 24'h000000;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0;
            O_tdata <= 0; O_tvalid <= 0; O_tuser <= 0; O_tlast <= 0;
        end else begin
            O_tdata <= rendered;
            O_tvalid <= I_tvalid;
            O_tuser <= I_tuser;
            O_tlast <= I_tlast;
            if (I_tuser) begin x <= 0; y <= 0; end
            if (I_tvalid) begin
                if (I_tlast || current_x == IMG_WIDTH-4) begin
                    x <= 0;
                    y <= current_y + 1'b1;
                end else begin
                    x <= current_x + 12'd4;
                    y <= current_y;
                end
            end
        end
    end
endmodule
