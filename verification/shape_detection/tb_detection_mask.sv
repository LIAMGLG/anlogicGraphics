`timescale 1ns/1ps
module tb_detection_mask;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,enable=1,cv=0,cd=0,update=0,valid=0,user=0,last=0;
    reg [8:0] mx=0;reg [7:0] my=0;reg [1:0] color=0;
    reg [95:0] data={4{24'h123456}};
    wire [95:0] result;wire ov,ou,ol;
    detection_mask_osd_rgb96 #(.IMG_WIDTH(160),.MASK_WIDTH(16),.MASK_HEIGHT(8),
        .PREVIEW_X(16),.PREVIEW_Y(16),.ADDRESS_BITS(5)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_enable(enable),.I_capture_valid(cv),.I_capture_done(cd),
        .I_result_update(update),.I_x(mx),.I_y(my),.I_color(color),
        .I_tdata(data),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
        .O_tdata(result),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol));
    `include "verification/shape_detection/golden_font.vh"
    integer x,y,lane,px,frame,shown=-1,checks=0;
    reg [95:0] wanted,e0,e1;
    reg v0=0,v1=0,u0=0,u1=0,l0=0,l1=0;
    reg [15:0] bits;reg [63:0] caption="MASK V4 ";reg [7:0] ch;
    function [23:0] rgb(input integer c);
        case(c) 1:rgb=24'hff4040;2:rgb=24'h40ff40;3:rgb=24'h4080ff;default:rgb=0;endcase
    endfunction
    task capture(input integer pattern);
        integer a,b;
        begin
            for(b=0;b<8;b=b+1) for(a=0;a<16;a=a+1) begin
                @(negedge clk);cv=1;cd=(b==7 && a==15);mx=a;my=b;color=(a+b+pattern)%4;
                // Accepted pixels may have gaps; packing must not shift on gaps.
                @(negedge clk);cv=0;cd=0;
            end
        end
    endtask
    task publish;
        begin @(negedge clk);update=1;@(negedge clk);update=0;end
    endtask
    always @(posedge clk) if(rst) begin
        e0<=wanted;e1<=e0;v0<=valid;v1<=v0;u0<=user;u1<=u0;l0<=last;l1<=l0;
        #1;
        if(ov!==v1 || ou!==u1 || ol!==l1) $fatal(1,"Mask control alignment");
        if(v1) begin checks=checks+1;if(result!==e1)
            $fatal(1,"Mask frame=%0d y=%0d x=%0d got=%h wanted=%h",frame,y,x,result,e1);end
    end
    initial begin
        wanted=data;repeat(4) @(negedge clk);rst=1;
        for(frame=0;frame<5;frame=frame+1) begin
            if(frame==1) begin capture(1);publish();shown=1;end
            if(frame==2) shown=2;
            if(frame==3) enable=0;
            if(frame==4) begin enable=1;shown=3;end
            for(y=0;y<56;y=y+1) for(x=0;x<160;x=x+4) begin
                // Mid-frame capture/publication must leave the current mask
                // immutable, and a further capture must not overwrite pending.
                if(frame==1 && y==8 && x==0) begin capture(2);publish();capture(3);end
                if(frame==3 && y==8 && x==0) publish();
                @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==156);
                wanted=data;
                for(lane=0;lane<4;lane=lane+1) begin
                    px=x+lane;
                    if(enable) begin
                        if(px>=16 && px<32 && y>=16 && y<24)
                            wanted[95-lane*24 -:24]=shown<0 ? 0 : rgb((px-16+y-16+shown)%4);
                        else if(px>=12 && px<36 && y>=12 && y<28)
                            wanted[95-lane*24 -:24]=24'hffffff;
                        if(px>=16 && px<144 && y>=36 && y<52) begin
                            ch=caption[63-((px-16)/16)*8 -:8];bits=golden_font(ch,y-36);
                            wanted[95-lane*24 -:24]=bits[15-(px-16)%16] ? 24'hfff200 : 0;
                        end
                    end
                end
                // Deassert video while the capture task runs at the next beat.
                @(negedge clk);valid=0;user=0;last=0;
            end
        end
        repeat(4) @(negedge clk);
        if(checks!=5*56*40) $fatal(1,"Mask output count");
        $display("PASS: exact mask packing, three banks, pending/current frame isolation, caption, disable, gaps, controls");$finish;
    end
endmodule
