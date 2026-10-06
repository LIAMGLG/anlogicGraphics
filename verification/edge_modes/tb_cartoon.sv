`timescale 1ns/1ps
module tb_cartoon;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, valid=0, user=0, last=0;
    reg [95:0] data=0, wanted=0;
    wire [95:0] edges, cartoon;
    wire edge_valid;
    edge_detect_96 #(.IMG_WIDTH(16),.IMG_HEIGHT(6),.EDGE_TH(80)) edge_dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_edge_th(11'd80),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),
        .I_tdata(data),.I_tready(),.O_tready(1'b1),.O_tdata(edges),
        .O_tlast(),.O_tuser(),.O_tvalid(edge_valid));
    cartoon_96 #(.IMG_WIDTH(16),.IMG_HEIGHT(6)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),
        .I_tdata(data),.I_edge_data(edges),.O_tdata(cartoon));
    reg [23:0] pixels [0:5][0:15];
    integer gray [0:5][0:7];
    reg [95:0] expected_d1=0, expected_d2=0;
    reg v1=0,v2=0;
    integer frame,y,x,lane,p,s,r,g,b,a,c,gx,gy,mag,checked=0;
    reg [23:0] center;
    function integer luminance;
        input [23:0] rgb;
        begin luminance=(rgb[23:16]/4)+(rgb[15:8]/2)+(rgb[7:0]/4); end
    endfunction
    function [23:0] posterized;
        input [23:0] a,b;
        integer r,g,bl;
        begin
            r=((a[23:16]+b[23:16])/2/64)*85;
            g=((a[15:8]+b[15:8])/2/64)*85;
            bl=((a[7:0]+b[7:0])/2/64)*85;
            posterized={r[7:0],g[7:0],bl[7:0]};
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin expected_d1<=0;expected_d2<=0;v1<=0;v2<=0; end
        else begin
            expected_d1<=wanted;expected_d2<=expected_d1;v1<=valid;v2<=v1;
            #1;
            if(edge_valid !== v2 || cartoon !== expected_d2)
                $fatal(1,"Cartoon mismatch got=%h expected=%h valid=%b",cartoon,expected_d2,v2);
            if(v2) checked=checked+1;
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            for(y=0;y<6;y=y+1) begin
                for(x=0;x<16;x=x+1) begin
                    case(frame)
                        0: begin r=99;g=140;b=211;end
                        1: begin r=x<8 ? 20:255;g=x<8 ? 30:255;b=x<8 ? 40:255;end
                        2: begin r=(x*43+y*29)%256;g=(x*17+y*41)%256;b=(x*31+y*11)%256;end
                    endcase
                    pixels[y][x]={r[7:0],g[7:0],b[7:0]};
                end
                for(x=0;x<8;x=x+1)
                    gray[y][x]=(luminance(pixels[y][x*2])+luminance(pixels[y][x*2+1]))/2;
            end
            if(frame==1) begin
                @(negedge clk);user=1;valid=0;wanted=0;
                @(negedge clk);user=0;
            end
            for(y=0;y<6;y=y+1) begin
                for(x=0;x<4;x=x+1) begin
                    @(negedge clk);valid=1;user=(frame!=1 && y==0 && x==0);last=(x==3);
                    for(lane=0;lane<4;lane=lane+1) data[95-lane*24 -:24]=pixels[y][x*4+lane];
                    wanted=0;
                    if(y>=1 && x>0) begin
                        for(p=0;p<2;p=p+1) begin
                            s=2*x+p;
                            center=posterized(pixels[y-1][(s-1)*2],pixels[y-1][(s-1)*2+1]);
                            mag=0;
                            if(y>=2) begin
                                gx=-gray[y-2][s-2]+gray[y-2][s]-2*gray[y-1][s-2]+2*gray[y-1][s]
                                   -gray[y][s-2]+gray[y][s];
                                gy=gray[y-2][s-2]+2*gray[y-2][s-1]+gray[y-2][s]
                                   -gray[y][s-2]-2*gray[y][s-1]-gray[y][s];
                                mag=(gx<0 ? -gx:gx)+(gy<0 ? -gy:gy);
                            end
                            if(mag>=80) center=0;
                            wanted[95-p*48 -:48]={center,center};
                        end
                    end
                    if(frame==2) begin
                        @(negedge clk);valid=0;user=0;last=0;wanted=0;
                    end
                end
            end
        end
        @(negedge clk);valid=0;user=0;last=0;wanted=0;
        repeat(4) @(negedge clk);
        if(checked!=72) $fatal(1,"Pixel beat count mismatch %d",checked);
        rst_n=0;#1;if(cartoon!==0) $fatal(1,"Reset mismatch");
        $display("PASS: cartoon color quantization, black contours, Sobel center alignment, continuous beats, bubbles and frame borders");
        $finish;
    end
endmodule
