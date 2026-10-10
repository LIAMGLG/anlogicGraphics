// Draw four colored bounding boxes, numbered legend and per-color counts.
// Results and enable are snapshotted at SOF. Three-cycle video/control latency.
module detection_overlay_rgb96 #(
    parameter integer IMG_WIDTH=1280,DIAGNOSTICS=0
)(
    input wire I_clk,I_rst_n,I_enable,
    input wire [255:0] I_boxes,
    input wire [2:0] I_count,
    input wire I_overflow,
    input wire [31:0] I_debug,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    reg [255:0] boxes;
    reg [31:0] debug_info;
    reg [2:0] count;
    reg overflow,enabled;
    wire [255:0] frame_boxes=boxes;
    wire [2:0] frame_count=count;
    wire frame_overflow=overflow;
    wire frame_enabled=enabled;
    reg [11:0] x;
    reg [10:0] y;
    wire [11:0] input_x=I_tuser ? 12'd0 : x;
    wire [10:0] input_y=I_tuser ? 11'd0 : y;
    reg [11:0] cx;
    reg [10:0] cy;
    reg [95:0] input_data;
    reg input_valid,input_user,input_last;
    wire [11:0] tx=cx-12'd16;
    wire [10:0] ty=cy-11'd96;
    reg [2:0] nr,ng;
    reg [127:0] summary;
    reg [127:0] legend;
    reg [127:0] diagnostic;
    reg [7:0] debug_byte;
    wire [10:0] debug_y=cy-11'd176;
    wire [63:0] debug_box=frame_boxes[debug_y[5:4]*64 +:64];
    reg [63:0] entry;
    reg [63:0] stat_box;
    reg [7:0] character;
    reg [3:0] font_row;
    wire [15:0] glyph;
    reg [15:0] border_hit,tab_hit,tab_ink;
    reg [15:0] border_d,tab_d,ink_d;
    reg [95:0] colors_d,colors;
    reg [23:0] box_color;
    reg [63:0] b;
    reg [10:0] px;
    reg [3:0] column;
    integer obj,lane,stat;
    wire [63:0] number_glyph;
    genvar number;
    generate for(number=0;number<4;number=number+1) begin: g_number
        wire [63:0] numbered_box=frame_boxes[number*64 +:64];
        wire [10:0] number_y=cy-numbered_box[47:38];
        localparam [7:0] NUMBER_CHAR=8'h31+number;
        osd_char_lib u_number_font (.I_char(NUMBER_CHAR),.I_row(number_y[3:0]),
            .O_row_bits(number_glyph[number*16 +:16]));
    end endgenerate
    reg [95:0] data_d;
    reg valid_d,user_d,last_d;
    reg [7:0] character_d;
    reg [3:0] font_row_d,column_d;
    reg panel_d;
    reg [95:0] text_marked;
    integer text_lane,text_obj;
    reg [3:0] text_column;
    function [23:0] color_rgb;
        input [1:0] c;
        begin case(c)
            1: color_rgb=24'hff4040;
            2: color_rgb=24'h40ff40;
            3: color_rgb=24'h4080ff;
            default: color_rgb=24'hffffff;
        endcase end
    endfunction
    always @(*) begin
        nr=0; ng=0;
        stat_box=0;
        for(stat=0;stat<4;stat=stat+1) begin
            stat_box=frame_boxes[stat*64 +:64];
            if(stat_box[63]) case(stat_box[62:61])
                1: nr=nr+1'b1; 2: ng=ng+1'b1;
            endcase
        end
        summary="N:0 R:0 G:0     ";
        summary[111:104]=8'h30+frame_count;
        summary[79:72]=8'h30+nr;
        summary[47:40]=8'h30+ng;
        if(frame_overflow) summary="LABEL OVERFLOW  ";
        entry=0;
        if(ty<64) entry=frame_boxes[ty[5:4]*64 +:64];
        legend="                ";
        if(entry[63]) begin
            case(entry[62:61])
                1: legend="1 RED           ";
                2: legend="1 GREEN         ";
                3: legend="1 BLUE          ";
                default: legend="1 UNKNOWN       ";
            endcase
            legend[127:120]=8'h31+ty[5:4];
            case(entry[60:59])
                1: legend[63:0]="RECT    ";
                2: legend[63:0]="CIRCLE  ";
                3: legend[63:0]="TRIANGLE";
                default: legend[63:0]="UNKNOWN ";
            endcase
        end
        character=8'h20; font_row=0;
        diagnostic="                ";debug_byte=0;
        if(DIAGNOSTICS && debug_y<64 && debug_box[63]) begin
            debug_byte=debug_info[debug_y[5:4]*8 +:8];
            diagnostic="1 V:00 E:0      ";
            diagnostic[127:120]=8'h31+debug_y[5:4];
            diagnostic[95:88]=debug_byte[7:4]>=10 ? 8'h31 : 8'h30;
            diagnostic[87:80]=8'h30+(debug_byte[7:4]>=10 ? debug_byte[7:4]-10 : debug_byte[7:4]);
            diagnostic[55:48]=8'h30+debug_byte[3:0];
        end
        if(cx>=16 && cx<272) begin
            if(cy>=64 && cy<80) begin
                character=summary[127-tx[7:4]*8 -:8]; font_row=cy-64;
            end else if(cy>=96 && cy<160) begin
                character=legend[127-tx[7:4]*8 -:8]; font_row=ty[3:0];
            end else if(DIAGNOSTICS && cy>=176 && cy<240) begin
                character=diagnostic[127-tx[7:4]*8 -:8];font_row=debug_y[3:0];
            end
        end
    end
    osd_char_lib u_font (.I_char(character_d),.I_row(font_row_d),.O_row_bits(glyph));
    always @(*) begin
        border_hit=0;tab_hit=0;tab_ink=0;colors=0; box_color=0; b=0; px=0; column=0;
        for(lane=0;lane<4;lane=lane+1) begin
            px=cx+lane;
            if(frame_enabled) begin
                // Low-priority boxes first; object 1 wins if boxes intersect.
                for(obj=3;obj>=0;obj=obj-1) begin
                    b=frame_boxes[obj*64 +:64];
                    box_color=color_rgb(b[62:61]);
                    colors[obj*24 +:24]=box_color;
                    if(b[63] && px>=b[58:48] && px<=b[37:27] && cy>=b[47:38] && cy<=b[26:17] &&
                      (px<b[58:48]+2 || px+2>b[37:27] || cy<b[47:38]+2 || cy+2>b[26:17]))
                        border_hit[obj*4+lane]=1;
                    // Numbered 16x16 tab maps each target to the fixed legend.
                    if(b[63] && px>=b[58:48] && px<b[58:48]+16 && cy>=b[47:38] && cy<b[47:38]+16)
                        begin
                        tab_hit[obj*4+lane]=1;
                        tab_ink[obj*4+lane]=number_glyph[obj*16+15-(px-b[58:48])];
                    end
                end
            end
        end
    end
    always @(*) begin
        text_marked=data_d;text_column=0;
        for(text_lane=0;text_lane<4;text_lane=text_lane+1) begin
            text_column=column_d+text_lane;
            for(text_obj=3;text_obj>=0;text_obj=text_obj-1) begin
                if(border_d[text_obj*4+text_lane]) text_marked[95-text_lane*24 -:24]=colors_d[text_obj*24 +:24];
                if(tab_d[text_obj*4+text_lane]) text_marked[95-text_lane*24 -:24]=ink_d[text_obj*4+text_lane] ? 24'hffffff : 24'h000000;
            end
            if(panel_d) text_marked[95-text_lane*24 -:24]=glyph[15-text_column] ? 24'hfff200 : 24'h000000;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            boxes<=0; debug_info<=0;count<=0; overflow<=0; enabled<=1;
            x<=0; y<=0; data_d<=0; valid_d<=0; user_d<=0; last_d<=0;
            border_d<=0;tab_d<=0;ink_d<=0;colors_d<=0;
            cx<=0;cy<=0;input_data<=0;input_valid<=0;input_user<=0;input_last<=0;
            character_d<=0;font_row_d<=0;column_d<=0;panel_d<=0;
            O_tdata<=0; O_tvalid<=0; O_tuser<=0; O_tlast<=0;
        end else begin
            if(I_tuser) begin
                boxes<=I_boxes;debug_info<=I_debug; count<=I_count; overflow<=I_overflow; enabled<=I_enable;
                x<=0; y<=0;
            end
            if(I_tvalid) begin
                if(I_tlast || input_x==IMG_WIDTH-4) begin x<=0; y<=input_y+1'b1; end
                else begin x<=input_x+4; y<=input_y; end
            end
            cx<=input_x;cy<=input_y;input_data<=I_tdata;
            input_valid<=I_tvalid;input_user<=I_tuser;input_last<=I_tlast;
            border_d<=border_hit;tab_d<=tab_hit;ink_d<=tab_ink;colors_d<=colors;
            data_d<=input_data; valid_d<=input_valid; user_d<=input_user; last_d<=input_last;
            character_d<=character;font_row_d<=font_row;column_d<=tx[3:0];
            panel_d<=frame_enabled && cx>=16 && cx<272 &&
                ((cy>=64 && cy<80) || (cy>=96 && cy<160 && entry[63]) ||
                 (DIAGNOSTICS && cy>=176 && cy<240 && debug_box[63]));
            O_tdata<=text_marked; O_tvalid<=valid_d; O_tuser<=user_d; O_tlast<=last_d;
        end
    end
endmodule
