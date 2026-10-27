// Sparse, centred power-of-two ROI: 128x64 samples at 8-pixel spacing at 720p.
// Read-only video tap; never gates SOF, pixels, ready or the camera reset.
module image_stats_rgb96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
)(
    input wire I_clk,I_rst_n,I_tuser,I_tvalid,I_tlast,
    input wire [95:0] I_tdata,
    output reg O_valid,O_high,
    output reg [7:0] O_luma,
    output reg [31:0] O_r,O_g,O_b,
    output reg O_neutral_valid
);
    localparam LX=$clog2(IMG_WIDTH/8+1)-1;
    localparam LY=$clog2(IMG_HEIGHT/8+1)-1;
    localparam NLOG=LX+LY, N=1<<NLOG, SW=8+NLOG;
    localparam X0=(IMG_WIDTH/4-(1<<LX)*2)/2;
    localparam Y0=(IMG_HEIGHT-(1<<LY)*8)/2;
    localparam MIN_NEUTRAL=(N/64<8) ? 8 : N/64;
    reg [$clog2(IMG_WIDTH/4)-1:0] x;
    reg [$clog2(IMG_HEIGHT)-1:0] y;
    reg armed,bad;
    wire [$clog2(IMG_WIDTH/4)-1:0] cx=I_tuser ? 0 : x;
    wire [$clog2(IMG_HEIGHT)-1:0] cy=I_tuser ? 0 : y;
    wire [7:0] r=I_tdata[23:16],g=I_tdata[15:8],b=I_tdata[7:0];
    wire [7:0] hi=(r>g ? (r>b ? r:b) : (g>b ? g:b));
    wire [7:0] lo=(r<g ? (r<b ? r:b) : (g<b ? g:b));
    wire [9:0] luma={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
    wire sample=cx>=X0 && cx<X0+(1<<LX)*2 && ((cx-X0)&1)==0 &&
                cy>=Y0 && cy<Y0+(1<<LY)*8 && ((cy-Y0)&7)==0;
    wire neutral=lo>=16 && hi<240 && {1'b0,lo,1'b0}>={2'b0,hi};
    reg [SW-1:0] sr,sg,sb,sy;
    reg [NLOG:0] nc,hc;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;armed<=0;bad<=0;sr<=0;sg<=0;sb<=0;sy<=0;nc<=0;hc<=0;
            O_valid<=0;O_high<=0;O_luma<=0;O_r<=0;O_g<=0;O_b<=0;O_neutral_valid<=0;
        end else begin
            O_valid<=0;
            if(I_tuser) begin
                x<=0;y<=0;armed<=1;bad<=0;sr<=0;sg<=0;sb<=0;sy<=0;nc<=0;hc<=0;
            end
            if((armed || I_tuser) && I_tvalid) begin
                if(I_tlast && cx!=IMG_WIDTH/4-1) bad<=1;
                if(cx==IMG_WIDTH/4-1) begin x<=0;y<=cy+1'b1;end
                else begin x<=cx+1'b1;y<=cy;end
                if(sample) begin
                    sy<=(I_tuser ? 0:sy)+luma[9:2];
                    hc<=(I_tuser ? 0:hc)+(hi>=248);
                    if(neutral) begin
                        sr<=(I_tuser ? 0:sr)+r;sg<=(I_tuser ? 0:sg)+g;sb<=(I_tuser ? 0:sb)+b;
                        nc<=(I_tuser ? 0:nc)+1'b1;
                    end
                end
                if(cx==IMG_WIDTH/4-1 && cy==IMG_HEIGHT-1) begin
                    armed<=0;
                    // The last ROI sample precedes the last beat (8-pixel grid).
                    O_valid<=!bad;O_luma<=sy>>NLOG;O_high<=hc>=(N/32);
                    O_r<=sr;O_g<=sg;O_b<=sb;O_neutral_valid<=nc>=MIN_NEUTRAL;
                end
            end
        end
    end
endmodule
