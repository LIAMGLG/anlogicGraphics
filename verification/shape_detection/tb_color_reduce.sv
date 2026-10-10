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
                c0<=r>=80 && r>=g+32 && r>=b+32 && 4*(r-g)>=r && 4*(r-b)>=r ? 1 :
                    g>=80 && g>=r+32 && g>=b+32 && 4*(g-r)>=g && 4*(g-b)>=g ? 2 :
                    b>=80 && b>=r+32 && b>=g+32 && 4*(b-r)>=b && 4*(b-g)>=b ? 3 : 0;
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
        for(phase=0;phase<14;phase=phase+1) begin
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
                    endcase
                    data[95-lane*24 -:24]=sample;
                end
                if(phase%2 && beat%7==0) begin @(negedge clk);valid=0;user=0;last=0; end
            end
        end
        @(negedge clk);valid=0;user=0;last=0;repeat(4) @(negedge clk);
        if(checks!=14*16*12) $fatal(1,"Reducer sample count %0d",checks);
        $display("PASS: 4x4 RGB average, absolute/relative color thresholds, tinted white rejection, boundary, noise, coordinates, gaps and SOF timings");
        $finish;
    end
endmodule
