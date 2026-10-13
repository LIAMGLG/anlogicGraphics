// Three-clock latency matches detection_overlay_rgb96, so mode selection
// adds no latency to the existing video chain. Regions are latched at SOF.
module motion_overlay_rgb96 #(
    parameter integer IMG_WIDTH=1280
)(
    input wire I_clk,I_rst_n,I_enable,I_motion,I_ready,
    input wire [143:0] I_regions,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast,O_motion
);
    reg [11:0] x;
    reg [10:0] y;
    reg [6:0] tile_x,tile_y;
    reg [3:0] col,row;
    reg [143:0] regions;
    reg enabled,motion,ready;
    wire frame_enable=I_tuser ? I_enable : enabled;
    wire frame_motion=I_tuser ? I_motion : motion;
    wire frame_ready=I_tuser ? I_ready : ready;
    wire [143:0] frame_regions=I_tuser ? I_regions : regions;
    wire [11:0] cx=I_tuser ? 12'd0 : x;
    wire [10:0] cy=I_tuser ? 11'd0 : y;
    wire [6:0] tx=I_tuser ? 7'd0 : tile_x;
    wire [6:0] ty=I_tuser ? 7'd0 : tile_y;
    wire [3:0] cc=I_tuser ? 4'd0 : col;
    wire [3:0] rr=I_tuser ? 4'd0 : row;
    wire marked=frame_regions[{rr,cc}];
    wire panel=cx>=16 && cx<144 && cy>=64 && cy<80;
    wire [11:0] local_x=cx-16;
    reg [7:0] character;
    wire [15:0] glyph;
    wire any_motion=|frame_regions;
    always @(*) begin
        character=" ";
        case(local_x[6:4])
            0: character= !frame_ready ? "W" : (any_motion ? "M" : "S");
            1: character= !frame_ready ? "A" : (any_motion ? "O" : "T");
            2: character= !frame_ready ? "I" : (any_motion ? "V" : "I");
            3: character= !frame_ready ? "T" : (any_motion ? "E" : "L");
            4: character= !frame_ready ? " " : (any_motion ? " " : "L");
            default:character=" ";
        endcase
    end
    osd_char_lib u_font(.I_char(character),.I_row(cy[3:0]),.O_row_bits(glyph));
    reg [95:0] rendered,d1,d2;
    reg v1,v2,u1,u2,l1,l2,m1,m2;
    integer lane;
    always @(*) begin
        rendered=I_tdata;
        for(lane=0;lane<4;lane=lane+1) begin
            if(frame_enable && frame_motion) begin
                if(frame_ready && marked && (tx+lane<2 || tx+lane>=78 || ty<2 || ty>=78))
                    rendered[95-lane*24 -:24]=24'hfff200;
                if(panel) rendered[95-lane*24 -:24]=glyph[15-(local_x[3:0]+lane)] ? 24'hfff200 : 24'd0;
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;tile_x<=0;tile_y<=0;col<=0;row<=0;
            regions<=0;enabled<=0;motion<=0;ready<=0;
            d1<=0;d2<=0;v1<=0;v2<=0;u1<=0;u2<=0;l1<=0;l2<=0;m1<=0;m2<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_motion<=0;
        end else begin
            if(I_tuser) begin
                regions<=I_regions;enabled<=I_enable;motion<=I_motion;ready<=I_ready;
                x<=0;y<=0;tile_x<=0;tile_y<=0;col<=0;row<=0;
            end
            if(I_tvalid) begin
                if(I_tlast || cx==IMG_WIDTH-4) begin
                    x<=0;y<=cy+1'b1;tile_x<=0;col<=0;
                    if(ty==79) begin tile_y<=0;row<=rr+1'b1; end
                    else tile_y<=ty+1'b1;
                end else begin
                    x<=cx+4;
                    if(tx==76) begin tile_x<=0;col<=cc+1'b1; end
                    else tile_x<=tx+4;
                end
            end
            d1<=rendered;d2<=d1;O_tdata<=d2;
            v1<=I_tvalid;v2<=v1;O_tvalid<=v2;
            u1<=I_tuser;u2<=u1;O_tuser<=u2;
            l1<=I_tlast;l2<=l1;O_tlast<=l2;
            m1<=frame_motion;m2<=m1;O_motion<=m2;
        end
    end
endmodule
