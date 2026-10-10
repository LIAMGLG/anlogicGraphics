`timescale 1ns/1ps
module tb_shape_contour;
    localparam W=320,H=180;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,start=0;
    reg [8:0] seedx,minx,maxx;
    reg [7:0] seedy,miny,maxy;
    reg [16:0] area;
    reg [1:0] color=1,pixel;
    wire [15:0] address;
    wire done;
    wire [1:0] shape;
    wire [3:0] reason,vertex_count;
    reg [1:0] mask[0:W*H-1];
    shape_contour_classifier dut(
        .I_clk(clk),.I_rst_n(rst),.I_start(start),.I_seed_x(seedx),.I_seed_y(seedy),
        .I_min_x(minx),.I_max_x(maxx),.I_min_y(miny),.I_max_y(maxy),.I_area(area),
        .I_color(color),.I_pixel(pixel),.O_address(address),.O_done(done),.O_shape(shape),.O_reason(reason),.O_vertices(vertex_count));
    always @(posedge clk) pixel<=mask[address];
    integer typ,scale,angle,tilt,x,y,p,tests=0,waits,expected;
    real radius,rad,u,v,cs,sn,hw,hh;
    bit in_shape;
    task classify(input integer wanted);
        begin
            minx=W-1;miny=H-1;maxx=0;maxy=0;area=0;seedx=0;seedy=0;
            for(p=0;p<W*H;p=p+1) if(mask[p]==color) begin
                x=p%W;y=p/W;
                if(area==0) begin seedx=x;seedy=y;end
                area=area+1;
                if(x<minx) minx=x;if(x>maxx) maxx=x;
                if(y<miny) miny=y;if(y>maxy) maxy=y;
            end
            @(negedge clk);start=1;@(negedge clk);start=0;waits=0;
            while(!done && waits<200000) begin @(posedge clk);#1;waits=waits+1;end
            if(!done || shape!==wanted[1:0]) begin
                $display("contour debug reason=%0d vertices=%0d perimeter=%0d polygon2=%0d convex=%b angleok=%b failed=%b",reason,dut.vertices,dut.perimeter_q8,dut.polygon_abs,dut.convex,dut.rectangle_angles,dut.failed);
                for(p=0;p<dut.vertices;p=p+1) $display("vertex %0d: %0d,%0d",p,dut.vertex[p][16:8],dut.vertex[p][7:0]);
                $fatal(1,"Contour type=%0d scale=%0d angle=%0d tilt=%0d expected=%0d got=%0d area=%0d",typ,scale,angle,tilt,wanted,shape,area);
            end
            if(wanted!=0 && reason!=0) $fatal(1,"Accepted shape carries a rejection code");
            if(typ==4 && reason!=6) $fatal(1,"Ring must carry area/hole rejection code");
            tests=tests+1;repeat(2) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(typ=1;typ<=3;typ=typ+1)
            for(scale=0;scale<6;scale=scale+1)
                for(angle=0;angle<(typ==3 ? 360 : 180);angle=angle+5)
                    for(tilt=0;tilt<2;tilt=tilt+1) begin
                        case(scale) 0:radius=8;1:radius=12;2:radius=20;3:radius=32;4:radius=48;5:radius=60;endcase
                        rad=angle*3.141592653589793/180;cs=$cos(rad);sn=$sin(rad);
                        hw=typ==1 ? radius*1.20 : radius;
                        hh=typ==1 ? radius*0.60 : radius;
                        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) begin
                            u=cs*(x-160.3)+sn*(y-90.4);v=-sn*(x-160.3)+cs*(y-90.4);
                            // Affine shear and foreshortening model mild oblique views.
                            if(tilt) begin u=u-0.15*v;v=v/0.85;end
                            case(typ)
                                1:in_shape=u>=-hw && u<=hw && v>=-hh && v<=hh;
                                2:in_shape=(u*u+v*v)<=radius*radius;
                                3:in_shape=v>=-hh && v<=hh && u>=-hw*(v+hh)/(2*hh) && u<=hw*(v+hh)/(2*hh);
                            endcase
                            mask[y*W+x]=in_shape ? color : 0;
                        end
                        classify(typ);
                    end
        // Near-camera disk occupies 95% of image height, but is still complete.
        typ=2;scale=4;angle=0;tilt=0;
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1)
            mask[y*W+x]=((x-160)*(x-160)+(y-90)*(y-90)<=7225) ? color : 0;
        classify(2);
        // A ring must not become CIRCLE merely because its external outline is round.
        typ=4;scale=0;angle=0;tilt=0;
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) begin
            p=(x-160)*(x-160)+(y-90)*(y-90);
            mask[y*W+x]=(p<=1600 && p>=900) ? color : 0;
        end
        classify(0);
        // Existing bright/specular interior gaps do not alter the outer polygon.
        typ=5;
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1)
            mask[y*W+x]=(x>=100 && x<=200 && y>=50 && y<=130 &&
                !(x>=140 && x<=150 && y>=80 && y<=90)) ? color : 0;
        classify(1);
        $display("PASS: %0d contour cases, rectangle/circle 180 and triangle 360 every 5 degree, six scales, subpixel position, mild affine tilt, holes, reasons",tests);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Contour test timeout");end
endmodule
