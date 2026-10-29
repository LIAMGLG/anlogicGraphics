`timescale 1ns/1ps
module tb_color_reduce;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0;
    reg [95:0] data=0;
    wire ov;
    wire [1:0] oc;
    wire [8:0] ox;
    wire [7:0] oy;
    color_reduce_rgb96 #(.IMG_WIDTH(64),.IMG_HEIGHT(48)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),
        .O_valid(ov),.O_color(oc),.O_x(ox),.O_y(oy));
    integer rr[0:15],gg[0:15],bb[0:15];
    integer rx=0,ry=0,r,g,b,lane,phase,row,beat,pix,checks=0;
    reg e0=0,e1=0;
    reg [1:0] c0=0,c1=0;
    reg [8:0] x0=0,x1=0;
    reg [7:0] y0=0,y1=0;
    reg [23:0] sample;
    always @(posedge clk) begin
        if(!rst) begin rx=0;ry=0;e0<=0;e1<=0; end
        else begin
            if(user) begin rx=0;ry=0; end
            e0<=valid && ry%4==3; e1<=e0;
            c1<=c0; x1<=x0; y1<=y0;
            if(valid) begin
                if(ry%4==0) begin rr[rx]=0;gg[rx]=0;bb[rx]=0; end
                for(integer t=0;t<4;t=t+1) begin
                    rr[rx]=rr[rx]+data[95-t*24 -:8];
                    gg[rx]=gg[rx]+data[87-t*24 -:8];
                    bb[rx]=bb[rx]+data[79-t*24 -:8];
                end
                r=rr[rx]/16;g=gg[rx]/16;b=bb[rx]/16;
                c0<=r>=48 && r>=g+24 && r>=b+24 && r>=2*g && r>=2*b ? 1 :
                    g>=40 && g>=r+12 && g>=b+12 && 4*(g-r)>=g && 4*(g-b)>=g ? 2 : 0;
                x0<=rx;y0<=ry/4;
                if(last) begin rx=0;ry=ry+1; end else rx=rx+1;
            end
            #1;
            if(ov!==e1) $fatal(1,"Reducer valid");
            if(e1) begin
                checks=checks+1;
                if(oc!==c1 || ox!==x1 || oy!==y1)
                    $fatal(1,"Reducer average/color/coordinates got %0d at %0d,%0d expected %0d at %0d,%0d",oc,ox,oy,c1,x1,y1);
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(phase=0;phase<42;phase=phase+1) begin
            if(phase%2) begin @(negedge clk);valid=0;user=1;last=0; end
            for(row=0;row<48;row=row+1) for(beat=0;beat<16;beat=beat+1) begin
                @(negedge clk);valid=1;user=phase%2==0 && row==0 && beat==0;last=beat==15;
                for(lane=0;lane<4;lane=lane+1) begin
                    pix=beat*4+lane;
                    case(phase)
                        0: sample={8'd160+pix[7:0],8'd20,8'd10};
                        1: sample={8'd20,8'd130+pix[7:0],8'd10};
                        2: sample={8'd20,8'd10,8'd180+pix[7:0]};
                        3: sample=24'hffffff;
                        4: sample=row%4==0 && lane==0 ? 24'hff0000 : 24'h000000;
                        5: sample=24'h503030;
                        6: sample=24'h503130;
                        7: sample={pix[7:0],row[7:0],(pix+row)&8'hff};
                        8: sample=24'hc8eec8; // green-cast white: reject
                        9: sample=24'heec8c8; // red-cast white: reject
                        10: sample=24'hc8c8ee; // blue-cast white: reject
                        11: sample={8'd160,8'd224,8'd160}; // colored green: accept
                        12: sample={8'd168,8'd224,8'd168}; // 25% boundary: accept
                        13: sample={8'd169,8'd224,8'd168}; // below boundary: reject
                        14: sample={8'd60,8'd20,8'd15}; // dim red accepted
                        15: sample={8'd20,8'd60,8'd15}; // dim green
                        16: sample={8'd20,8'd15,8'd60}; // dim blue
                        17: sample={8'd10,8'd10,8'd39}; // below brightness floor
                        18: sample={8'd28,8'd28,8'd40}; // floor + absolute margin boundary
                        19: sample={8'd29,8'd28,8'd40}; // insufficient absolute margin
                        20: sample={8'd50,8'd60,8'd50}; // dim green-cast gray: reject
                        21: sample={8'd20,8'd44,8'd60}; // dim blue with green content
                        22: sample={8'd80,8'd48,8'd48}; // weak red now rejected
                        23: sample={8'd79,8'd20,8'd20}; // below old floor, now accepted
                        24: sample={8'd80,8'd49,8'd48}; // weak red now rejected
                        25: sample={8'd60,8'd45,8'd45}; // old 25% boundary now rejected
                        26: sample={8'd65,8'd65,8'd80}; // blue detection disabled: background
                        27: sample={8'd66,8'd65,8'd80}; // below blue relative boundary
                        28: sample={8'd65,8'd80,8'd65}; // green still requires 25%: reject
                        29: sample={8'd80,8'd65,8'd65}; // weak red: reject
                        30: sample={8'd200,8'd140,8'd110}; // warm skin-like RGB: reject
                        31: sample={8'd160,8'd95,8'd70}; // darker skin-like RGB: reject
                        32: sample={8'd240,8'd160,8'd140}; // bright skin-like RGB: reject
                        33: sample={8'd120,8'd60,8'd40}; // new red ratio boundary: accept
                        34: sample={8'd120,8'd61,8'd40}; // green just above half: reject
                        35: sample={8'd120,8'd40,8'd61}; // blue just above half: reject
                        36: sample={8'd47,8'd10,8'd10}; // below new red floor: reject
                        37: sample={8'd48,8'd24,8'd24}; // floor and margin boundary: accept
                        38: sample={8'd255,8'd128,8'd10}; // odd ratio rounds up: reject
                        39: sample={8'd255,8'd127,8'd127}; // bright boundary: accept
                        40: sample={8'd255,8'd250,8'd240}; // no bright-channel overflow
                        41: sample={8'd48,8'd25,8'd10}; // below absolute margin: reject
                    endcase
                    data[95-lane*24 -:24]=sample;
                end
                if(phase%2 && beat%7==0) begin @(negedge clk);valid=0;user=0;last=0; end
            end
        end
        @(negedge clk);valid=0;user=0;last=0;repeat(4) @(negedge clk);
        if(checks!=42*16*12) $fatal(1,"Reducer sample count %0d",checks);
        $display("PASS: 4x4 RGB average, stricter red purity, skin-like RGB rejection, green thresholds, boundary, noise, coordinates, gaps and SOF timings");
        $finish;
    end
endmodule
