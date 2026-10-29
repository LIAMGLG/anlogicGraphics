// Four-pixel RGB888 mode label, using the reference lab_ex3_osd character ROM.
// Pixel 0 occupies [95:72], matching data128_96 and the video packer.
// Fixed panel: x=16..239, y=16..47; 16x16 glyphs enlarged 2x.
// Adds one cycle to data and all stream control signals. No independent stall buffer.
module mode_osd_rgb96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer SHOW_EXPOSURE=1,AUTO_AE=1
)(
    input wire I_clk, I_rst_n,
    input wire [2:0] I_mode,
    input wire [29:0] I_exposure_status,
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
    wire inside_exposure=SHOW_EXPOSURE!=0 && current_x>=256 && current_x<800 &&
                         current_y>=16 && current_y<48;
    wire [11:0] exposure_x=current_x-12'd256;
    reg [29:0] exposure_status;
    reg [7:0] exposure_char;
    wire [2:0] mode=I_mode<=5 ? I_mode : 3'd0;
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
            6'd40:character="M";
            6'd41:character="O";
            6'd42:character="T";
            6'd43:character="I";
            6'd44:character="O";
            6'd45:character="N";
            default:character=8'h20;
        endcase
    end
    // Same character ROM and the same output register serve both panels.
    always @(*) begin
        exposure_char=8'h20;
        case(exposure_x[9:5])
            0:exposure_char=AUTO_AE ? "A":"M";
            1:exposure_char="E";
            3:exposure_char=8'h30+{4'd0,exposure_status[27:24]};
            4:exposure_char=8'h30+{4'd0,exposure_status[23:20]};
            5:exposure_char=".";
            6:exposure_char=8'h30+{4'd0,exposure_status[19:16]};
            7:exposure_char="M";
            8:exposure_char="S";
            10:exposure_char="G";
            11:exposure_char=8'h30+{4'd0,exposure_status[15:12]};
            12:exposure_char=8'h30+{4'd0,exposure_status[11:8]};
            13:exposure_char=".";
            14:exposure_char=8'h30+{4'd0,exposure_status[7:4]};
            15:exposure_char=8'h30+{4'd0,exposure_status[3:0]};
            16:exposure_char="X";
            default:exposure_char=8'h20;
        endcase
        if(exposure_status[29] || !exposure_status[28]) case(exposure_x[9:5])
            0:exposure_char=AUTO_AE ? "A":"M";
            1:exposure_char="E";
            3:exposure_char=exposure_status[29] ? "E":"W";
            4:exposure_char=exposure_status[29] ? "R":"A";
            5:exposure_char=exposure_status[29] ? "R":"I";
            6:exposure_char=exposure_status[29] ? " ":"T";
            default:exposure_char=8'h20;
        endcase
    end
    wire [15:0] font_glyph;
    // Exposure digits use the same six-column, eight-row footprint and baseline
    // as the legacy Latin letters (font rows 2..9), with the same 2x scaling.
    // Keep this override local: other panels still use the original font ROM.
    function [15:0] exposure_number_row;
        input [7:0] ch;
        input [3:0] row;
        reg [63:0] bitmap;
        begin
            case(ch)
                "0":bitmap=64'h1e3333333333331e;
                "1":bitmap=64'h0c1c0c0c0c0c0c1e;
                "2":bitmap=64'h1e3303060c18303f;
                "3":bitmap=64'h1e3303030e03331e;
                "4":bitmap=64'h060e1636363f0606;
                "5":bitmap=64'h3f30303e0303331e;
                "6":bitmap=64'h1e3330303e33331e;
                "7":bitmap=64'h3f0303060c0c1818;
                "8":bitmap=64'h1e33331e3333331e;
                "9":bitmap=64'h1e33331f0303331e;
                default:bitmap=0;
            endcase
            exposure_number_row=0;
            if(row>=2 && row<=9)
                exposure_number_row={bitmap[63-(row-2)*8 -:8],8'd0};
        end
    endfunction
    assign glyph = inside_exposure && exposure_char>="0" && exposure_char<="9" ?
                   exposure_number_row(exposure_char,local_y[4:1]) :
                   inside_exposure && exposure_char=="." ?
                   ((local_y[4:1]==8 || local_y[4:1]==9) ? 16'h0c00 : 16'd0) : font_glyph;
    osd_char_lib u_font (.I_char(inside_exposure ? exposure_char:character), .I_row(local_y[4:1]), .O_row_bits(font_glyph));

    // Panel origin, character pitch and input groups are all four-pixel aligned,
    // so a single character row serves all four lanes.
    always @(*) begin
        rendered = I_tdata;
        column = 0;
        for (lane=0; lane<4; lane=lane+1) begin
            column = (local_x[4:0] + lane) >> 1;
            if (inside_panel)
                rendered[95-lane*24 -: 24] = glyph[15-column] ? 24'hfff200 : 24'h000000;
            if (inside_exposure) begin
                column=(exposure_x[4:0]+lane)>>1;
                rendered[95-lane*24 -:24]=glyph[15-column] ? 24'hfff200:24'h000000;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0;
            O_tdata <= 0; O_tvalid <= 0; O_tuser <= 0; O_tlast <= 0;
            exposure_status<=0;
        end else begin
            O_tdata <= rendered;
            O_tvalid <= I_tvalid;
            O_tuser <= I_tuser;
            O_tlast <= I_tlast;
            if(I_tuser) exposure_status<=I_exposure_status;
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
