// Transparent Anlogic logo, 160x96, bottom-right of the 1280x720 frame.
// Packed synchronous ROM and aligned video add two clocks of latency.
module logo_osd_rgb96 #(
    parameter integer IMG_WIDTH=1280,LOGO_X=1104,LOGO_Y=608
)(
    input wire I_clk,I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    reg [11:0] x;
    reg [10:0] y;
    wire [11:0] cx=I_tuser ? 12'd0 : x;
    wire [10:0] cy=I_tuser ? 11'd0 : y;
    wire inside_logo=cx>=LOGO_X && cx<LOGO_X+160 && cy>=LOGO_Y && cy<LOGO_Y+96;
    wire [11:0] local_y=cy-LOGO_Y;
    wire [11:0] local_x=cx-LOGO_X;
    wire [11:0] address=inside_logo ? (local_y<<5)+(local_y<<3)+(local_x>>2) : 12'd0;
    wire [99:0] pixels;
    reg [95:0] data_d;
    reg inside_d,valid_d,user_d,last_d;
    integer lane;
    anlogic_logo_words u_rom(.I_clk(I_clk),.I_addr(address),.O_pixels(pixels));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;data_d<=0;inside_d<=0;valid_d<=0;user_d<=0;last_d<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            data_d<=I_tdata;inside_d<=inside_logo;
            valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tlast;
            for(lane=0;lane<4;lane=lane+1)
                O_tdata[95-lane*24 -:24]<=inside_d && pixels[99-lane*25] ?
                    pixels[98-lane*25 -:24] : data_d[95-lane*24 -:24];
            O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;
            if(I_tuser) begin x<=0;y<=0;end
            if(I_tvalid) begin
                if(I_tlast || cx==IMG_WIDTH-4) begin x<=0;y<=cy+1'b1;end
                else begin x<=cx+4;y<=cy;end
            end
        end
    end
endmodule
