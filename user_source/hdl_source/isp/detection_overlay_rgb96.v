// Draw four colored bounding boxes, numbered legend and per-color counts.
// Results and enable are snapshotted at SOF. Three-cycle video/control latency.
module detection_overlay_rgb96 #(
    parameter integer IMG_WIDTH=1280,COORDINATES=1
)(
    input wire I_clk,I_rst_n,I_enable,
    input wire [255:0] I_boxes,
    input wire [2:0] I_count,
    input wire I_overflow,
    input wire [3:0] I_held,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    reg [255:0] boxes;
    reg [3:0] held;
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
    reg [2:0] nr_next,ng_next;
    wire [10:0] coordinate_y=cy-11'd176;
    wire [63:0] coordinate_box=frame_boxes[coordinate_y[5:4]*64 +:64];
    // Eight center coordinates share one 12-bit shift/add-3 BCD converter.
    // Conversion starts at SOF and completes in 104 clocks, before row 176.
    reg [95:0] centers;
    reg [127:0] coordinates,working_digits;
    reg [11:0] binary_value;
    reg [15:0] decimal_value;
    reg [3:0] conversion_step;
    reg [2:0] coordinate_index;
    reg converting,coordinates_ready;
    reg [15:0] adjusted_bcd;
    wire [15:0] shifted_bcd={adjusted_bcd[14:0],binary_value[11]};
    wire [15:0] coordinate_x_bcd=coordinates[coordinate_y[5:4]*32 +:16];
    wire [15:0] coordinate_y_bcd=coordinates[coordinate_y[5:4]*32+16 +:16];
    integer digit,center_slot;
    function [11:0] center_x;
        input [63:0] r;
        reg [11:0] sum;
        begin sum={1'b0,r[58:48]}+{1'b0,r[37:27]};center_x=sum>>1;end
    endfunction
    function [11:0] center_y;
        input [63:0] r;
        reg [10:0] sum;
        begin sum={1'b0,r[47:38]}+{1'b0,r[26:17]};center_y={1'b0,sum}>>1;end
    endfunction
    always @(*) begin
        adjusted_bcd=decimal_value;
        for(digit=0;digit<4;digit=digit+1)
            if(decimal_value[digit*4 +:4]>=5)
                adjusted_bcd[digit*4 +:4]=decimal_value[digit*4 +:4]+4'd3;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            centers<=0;coordinates<=0;working_digits<=0;binary_value<=0;decimal_value<=0;
            conversion_step<=0;coordinate_index<=0;converting<=0;coordinates_ready<=0;
        end else if(I_tuser) begin
            for(center_slot=0;center_slot<4;center_slot=center_slot+1) begin
                centers[center_slot*24 +:12]<=center_x(I_boxes[center_slot*64 +:64]);
                centers[center_slot*24+12 +:12]<=center_y(I_boxes[center_slot*64 +:64]);
            end
            conversion_step<=0;coordinate_index<=0;converting<=COORDINATES!=0;coordinates_ready<=0;
        end else if(converting) begin
            if(conversion_step==0) begin
                binary_value<=centers[coordinate_index*12 +:12];decimal_value<=0;conversion_step<=1;
            end else begin
                decimal_value<=shifted_bcd;binary_value<={binary_value[10:0],1'b0};
                if(conversion_step==12) begin
                    working_digits[coordinate_index*16 +:16]<=shifted_bcd;conversion_step<=0;
                    if(coordinate_index==7) begin
                        coordinates<={shifted_bcd,working_digits[111:0]};converting<=0;coordinates_ready<=1;
                    end else coordinate_index<=coordinate_index+1'b1;
                end else conversion_step<=conversion_step+1'b1;
            end
        end
    end
    reg [63:0] entry;
    reg [63:0] stat_box;
    reg [7:0] character;
    reg [3:0] font_row;
    wire [15:0] glyph;
    reg [15:0] border_hit,tab_hit,tab_ink;
    reg [15:0] border_d,tab_d,ink_d;
    reg [95:0] colors_d,colors;
    reg [63:0] b;
    reg [10:0] px;
    reg [3:0] column;
    reg [3:0] y_inside,y_border,y_tab;
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
    function [7:0] overflow_char;
        input [3:0] col;
        begin case(col)
            4'd0:overflow_char=8'h4C;
            4'd1:overflow_char="A";
            4'd2:overflow_char="B";
            4'd3:overflow_char="E";
            4'd4:overflow_char="L";
            4'd6:overflow_char="O";
            4'd7:overflow_char="V";
            4'd8:overflow_char="E";
            4'd9:overflow_char="R";
            4'd10:overflow_char="F";
            4'd11:overflow_char="L";
            4'd12:overflow_char="O";
            4'd13:overflow_char="W";
            default:overflow_char=8'h20;
        endcase end
    endfunction
    function [7:0] color_char;
        input [1:0] kind;
        input [3:0] col;
        begin case({kind,col})
            6'd0:color_char=8'h55;
            6'd1:color_char=8'h4E;
            6'd2:color_char=8'h4B;
            6'd3:color_char=8'h4E;
            6'd4:color_char=8'h4F;
            6'd5:color_char=8'h57;
            6'd6:color_char=8'h4E;
            6'd16:color_char=8'h52;
            6'd17:color_char=8'h45;
            6'd18:color_char=8'h44;
            6'd32:color_char=8'h47;
            6'd33:color_char=8'h52;
            6'd34:color_char=8'h45;
            6'd35:color_char=8'h45;
            6'd36:color_char=8'h4E;
            6'd48:color_char=8'h42;
            6'd49:color_char=8'h4C;
            6'd50:color_char=8'h55;
            6'd51:color_char=8'h45;
            default:color_char=8'h20;
        endcase end
    endfunction
    function [7:0] shape_char;
        input [1:0] kind;
        input [3:0] col;
        begin case({kind,col})
            6'd0:shape_char=8'h55;
            6'd1:shape_char=8'h4E;
            6'd2:shape_char=8'h4B;
            6'd3:shape_char=8'h4E;
            6'd4:shape_char=8'h4F;
            6'd5:shape_char=8'h57;
            6'd6:shape_char=8'h4E;
            6'd16:shape_char=8'h52;
            6'd17:shape_char=8'h45;
            6'd18:shape_char=8'h43;
            6'd19:shape_char=8'h54;
            6'd32:shape_char=8'h43;
            6'd33:shape_char=8'h49;
            6'd34:shape_char=8'h52;
            6'd35:shape_char=8'h43;
            6'd36:shape_char=8'h4C;
            6'd37:shape_char=8'h45;
            6'd48:shape_char=8'h54;
            6'd49:shape_char=8'h52;
            6'd50:shape_char=8'h49;
            6'd51:shape_char=8'h41;
            6'd52:shape_char=8'h4E;
            6'd53:shape_char=8'h47;
            6'd54:shape_char=8'h4C;
            6'd55:shape_char=8'h45;
            default:shape_char=8'h20;
        endcase end
    endfunction
    always @(*) begin
        nr_next=0; ng_next=0;
        stat_box=0;
        for(stat=0;stat<4;stat=stat+1) begin
            stat_box=I_boxes[stat*64 +:64];
            if(stat_box[63] && !I_held[stat]) case(stat_box[62:61])
                1: nr_next=nr_next+1'b1; 2: ng_next=ng_next+1'b1;
            endcase
        end
    end
    always @(*) begin
        entry=0;
        if(ty<64) entry=frame_boxes[ty[5:4]*64 +:64];
        character=8'h20; font_row=0;
        if(cx>=16 && cx<272) begin
            if(cy>=64 && cy<80) begin
                font_row=cy-64;
                if(frame_overflow) character=overflow_char(tx[7:4]);
                else case(tx[7:4])
                    0:character="N";
                    1,5,9:character=":";
                    2:character=8'h30+frame_count;
                    4:character="R";
                    6:character=8'h30+nr;
                    8:character="G";
                    10:character=8'h30+ng;
                    default:character=8'h20;
                endcase
            end else if(cy>=96 && cy<160) begin
                font_row=ty[3:0];
                if(entry[63]) begin
                    if(tx[7:4]==0) character=8'h31+ty[5:4];
                    else if(tx[7:4]>=8 && held[ty[5:4]]) begin
                        case(tx[7:4])
                            8:character="W";9:character="A";10:character="I";11:character="T";
                            default:character=8'h20;
                        endcase
                    end else if(tx[7:4]>=8) character=shape_char(entry[60:59],{1'b0,tx[6:4]});
                    else if(tx[7:4]>=2) character=color_char(entry[62:61],tx[7:4]-4'd2);
                end
            end else if(COORDINATES && coordinates_ready && cy>=176 && cy<240) begin
                font_row=coordinate_y[3:0];
                if(coordinate_box[63]) case(tx[7:4])
                    0:character=8'h31+coordinate_y[5:4];
                    2:character="X";
                    3,10:character=":";
                    4:character=8'h30+coordinate_x_bcd[15:12];
                    5:character=8'h30+coordinate_x_bcd[11:8];
                    6:character=8'h30+coordinate_x_bcd[7:4];
                    7:character=8'h30+coordinate_x_bcd[3:0];
                    9:character="Y";
                    11:character=8'h30+coordinate_y_bcd[15:12];
                    12:character=8'h30+coordinate_y_bcd[11:8];
                    13:character=8'h30+coordinate_y_bcd[7:4];
                    14:character=8'h30+coordinate_y_bcd[3:0];
                    default:character=8'h20;
                endcase
            end
        end
    end
    osd_char_lib u_font (.I_char(character_d),.I_row(font_row_d),.O_row_bits(glyph));
    always @(*) begin
        border_hit=0;tab_hit=0;tab_ink=0;colors=0; b=0; px=0; column=0;
        y_inside=0;y_border=0;y_tab=0;
        // Vertical tests and color decode are shared by all four pixel lanes.
        for(obj=0;obj<4;obj=obj+1) begin
            b=frame_boxes[obj*64 +:64];
            colors[obj*24 +:24]=held[obj] ? 24'h909090 : color_rgb(b[62:61]);
            y_inside[obj]=b[63] && cy>=b[47:38] && cy<=b[26:17];
            y_border[obj]=cy<b[47:38]+2 || cy+2>b[26:17];
            y_tab[obj]=b[63] && cy>=b[47:38] && cy<b[47:38]+16;
        end
        for(lane=0;lane<4;lane=lane+1) begin
            px=cx+lane;
            if(frame_enabled) begin
                // Low-priority boxes first; object 1 wins if boxes intersect.
                for(obj=3;obj>=0;obj=obj-1) begin
                    b=frame_boxes[obj*64 +:64];
                    if(y_inside[obj] && px>=b[58:48] && px<=b[37:27] &&
                      (px<b[58:48]+2 || px+2>b[37:27] || y_border[obj]))
                        border_hit[obj*4+lane]=!held[obj] || (px[3]^cy[3])==1'b0;
                    // Numbered 16x16 tab maps each target to the fixed legend.
                    if(y_tab[obj] && px>=b[58:48] && px<b[58:48]+16)
                        begin
                        tab_hit[obj*4+lane]=1;
                        column=px-b[58:48];
                        tab_ink[obj*4+lane]=number_glyph[obj*16+15-column];
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
            boxes<=0;held<=0;count<=0; overflow<=0; enabled<=1;nr<=0;ng<=0;
            x<=0; y<=0; data_d<=0; valid_d<=0; user_d<=0; last_d<=0;
            border_d<=0;tab_d<=0;ink_d<=0;colors_d<=0;
            cx<=0;cy<=0;input_data<=0;input_valid<=0;input_user<=0;input_last<=0;
            character_d<=0;font_row_d<=0;column_d<=0;panel_d<=0;
            O_tdata<=0; O_tvalid<=0; O_tuser<=0; O_tlast<=0;
        end else begin
            if(I_tuser) begin
                boxes<=I_boxes;held<=I_held; count<=I_count; overflow<=I_overflow; enabled<=I_enable;
                nr<=nr_next;ng<=ng_next;
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
                 (COORDINATES && coordinates_ready && cy>=176 && cy<240 && coordinate_box[63]));
            O_tdata<=text_marked; O_tvalid<=valid_d; O_tuser<=user_d; O_tlast<=last_d;
        end
    end
endmodule
