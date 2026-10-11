`timescale 1ns/1ps
module tb_logo;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [11:0] address=0;
    wire [99:0] packed_pixels;
    reg [14:0] source_address=0;
    wire [24:0] source_pixel;
    reg [24:0] golden[0:15359];
    anlogic_logo_words rom(clk,address,packed_pixels);
    anlogic_logo_rom source_rom(source_address,source_pixel);
    reg [95:0] data=0;
    reg valid=0,user=0,last=0;
    wire [95:0] out_data;
    wire out_valid,out_user,out_last;
    logo_osd_rgb96 osd(clk,rst_n,data,valid,user,last,out_data,out_valid,out_user,out_last);
    function automatic [24:0] quantize(input [24:0] pixel);
        integer p,dr,dg,db,distance,best_distance;
        reg [23:0] colour,best_colour;
        begin
            best_distance=2147483647;best_colour=0;
            for(p=0;p<3;p=p+1) begin
                case(p) 0:colour=24'hED1C24;1:colour=24'h1C2D4E;2:colour=24'hFFFFFF;endcase
                dr=int'(pixel[23:16])-int'(colour[23:16]);
                dg=int'(pixel[15:8])-int'(colour[15:8]);
                db=int'(pixel[7:0])-int'(colour[7:0]);
                distance=dr*dr+dg*dg+db*db;
                if(distance<best_distance) begin best_distance=distance;best_colour=colour;end
            end
            quantize=pixel[24] ? {1'b1,best_colour} : 25'd0;
        end
    endfunction
    reg [95:0] previous_expected=0;
    reg previous_valid=0,previous_user=0,previous_last=0;
    integer checks=0;
    task automatic send(input integer x,input integer y,input bit v,input bit u,input bit l);
        reg [95:0] expected,background;
        reg [24:0] pixel;
        integer lane;
        begin
            background={24'h102030,24'h405060,24'h708090,24'hA0B0C0};
            expected=background;
            if(x>=1104 && x<1264 && y>=608 && y<704) begin
                for(lane=0;lane<4;lane=lane+1) begin
                    pixel=golden[(y-608)*160+x-1104+lane];
                    if(pixel[24]) expected[95-lane*24 -:24]=pixel[23:0];
                end
            end
            @(negedge clk);data=background;valid=v;user=u;last=l;
            @(posedge clk);#1;
            if({out_valid,out_user,out_last}!=={previous_valid,previous_user,previous_last})
                $fatal(1,"Logo video control alignment x=%0d y=%0d",x,y);
            if(previous_valid && out_data!==previous_expected)
                $fatal(1,"Logo pixel mismatch x=%0d y=%0d got=%h expected=%h",x,y,out_data,previous_expected);
            previous_expected=expected;previous_valid=v;previous_user=u;previous_last=l;
            checks=checks+1;
        end
    endtask
    integer i,lane,x,y,opaque=0;
    initial begin
        // Independent reference from the original RGB ROM, not generated indices.
        for(i=0;i<15360;i=i+1) begin
            source_address=i+5120;#1;
            golden[i]=quantize(source_pixel);
            if(source_pixel[24]) opaque=opaque+1;
        end
        if(opaque!=6387) $fatal(1,"Unexpected original transparency mask");
        for(i=0;i<3840;i=i+1) begin
            @(negedge clk);address=i;
            @(posedge clk);#1;
            for(lane=0;lane<4;lane=lane+1)
                if(packed_pixels[99-lane*25 -:25]!==golden[i*4+lane])
                    $fatal(1,"Palette ROM mismatch word=%0d lane=%0d",i,lane);
        end
        @(negedge clk);rst_n=1;
        // Two full frames, including blank cycles between lines.
        repeat(2) begin
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<1280;x=x+4) send(x,y,1,x==0 && y==0,x==1276);
                send(0,y+1,0,0,0);
            end
        end
        send(0,0,0,0,0);
        @(negedge clk);rst_n=0;valid=0;user=0;last=0;
        @(posedge clk);#1;
        if(out_data!==0 || {out_valid,out_user,out_last}!==0) $fatal(1,"Logo reset failed");
        previous_expected=0;previous_valid=0;previous_user=0;previous_last=0;
        @(negedge clk);rst_n=1;
        send(0,0,1,1,0);send(4,0,1,0,0);send(8,0,0,0,0);
        $display("PASS: three-colour logo, all 15360 pixels, transparency, four lanes, two full frames, controls and reset (%0d cycles)",checks);
        $finish;
    end
endmodule
