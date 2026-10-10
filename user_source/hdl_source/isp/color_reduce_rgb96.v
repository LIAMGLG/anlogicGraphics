// 4x4 box average followed by dominant-channel color segmentation.
// One 2-bit sample per four input rows; no backpressure on the video.
module color_reduce_rgb96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter [7:0] COLOR_MIN=80, COLOR_MARGIN=32
)(
    input wire I_clk, I_rst_n, I_tvalid, I_tuser, I_tlast,
    input wire [95:0] I_tdata,
    output reg O_valid,
    output reg [1:0] O_color,
    output reg [8:0] O_x,
    output reg [7:0] O_y
);
    localparam W=IMG_WIDTH/4;
    reg [8:0] x;
    reg [10:0] y;
    wire [8:0] cx=I_tuser ? 9'd0 : x;
    wire [10:0] cy=I_tuser ? 11'd0 : y;
    reg [35:0] sums [0:W-1];
    reg [35:0] previous;
    reg [9:0] sr,sg,sb;
    reg [8:0] sx;
    reg [10:0] sy;
    reg sv;
    wire [11:0] tr=(sy[1:0]==0 ? 12'd0 : previous[35:24])+sr;
    wire [11:0] tg=(sy[1:0]==0 ? 12'd0 : previous[23:12])+sg;
    wire [11:0] tb=(sy[1:0]==0 ? 12'd0 : previous[11:0])+sb;
    wire [7:0] r=tr[11:4], g=tg[11:4], b=tb[11:4];
    // Require both the absolute margin and >=25% dominance over EACH other
    // channel. A bright near-white pixel with a small green cast is background.
    // ceil(channel/4), implemented without multipliers or dividers.
    wire [7:0] relative_r={2'b0,r[7:2]} + (r[1:0]!=0);
    wire [7:0] relative_g={2'b0,g[7:2]} + (g[1:0]!=0);
    wire [7:0] relative_b={2'b0,b[7:2]} + (b[1:0]!=0);
    wire [7:0] margin_r=COLOR_MARGIN>relative_r ? COLOR_MARGIN : relative_r;
    wire [7:0] margin_g=COLOR_MARGIN>relative_g ? COLOR_MARGIN : relative_g;
    wire [7:0] margin_b=COLOR_MARGIN>relative_b ? COLOR_MARGIN : relative_b;
    // 9-bit comparisons prevent wrapping at bright channel values.
    wire red=(r>=COLOR_MIN) && ({1'b0,r}>={1'b0,g}+{1'b0,margin_r}) &&
                                  ({1'b0,r}>={1'b0,b}+{1'b0,margin_r});
    wire green=(g>=COLOR_MIN) && ({1'b0,g}>={1'b0,r}+{1'b0,margin_g}) &&
                                    ({1'b0,g}>={1'b0,b}+{1'b0,margin_g});
    wire blue=(b>=COLOR_MIN) && ({1'b0,b}>={1'b0,r}+{1'b0,margin_b}) &&
                                   ({1'b0,b}>={1'b0,g}+{1'b0,margin_b});
    always @(posedge I_clk) begin
        if (I_tvalid) previous<=sums[cx];
        if (sv) sums[sx]<={tr,tg,tb};
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0; y<=0; sv<=0; sr<=0; sg<=0; sb<=0; sx<=0; sy<=0;
            O_valid<=0; O_color<=0; O_x<=0; O_y<=0;
        end else begin
            sv<=I_tvalid; sx<=cx; sy<=cy;
            sr<={2'b0,I_tdata[95:88]}+{2'b0,I_tdata[71:64]}+{2'b0,I_tdata[47:40]}+{2'b0,I_tdata[23:16]};
            sg<={2'b0,I_tdata[87:80]}+{2'b0,I_tdata[63:56]}+{2'b0,I_tdata[39:32]}+{2'b0,I_tdata[15:8]};
            sb<={2'b0,I_tdata[79:72]}+{2'b0,I_tdata[55:48]}+{2'b0,I_tdata[31:24]}+{2'b0,I_tdata[7:0]};
            O_valid<=sv && sy[1:0]==3;
            O_x<=sx; O_y<=sy>>2;
            O_color<=red ? 2'd1 : green ? 2'd2 : blue ? 2'd3 : 2'd0;
            if(I_tuser) begin x<=0; y<=0; end
            if(I_tvalid) begin
                if(I_tlast || cx==W-1) begin x<=0; y<=cy+1'b1; end
                else begin x<=cx+1'b1; y<=cy; end
            end
        end
    end
endmodule
