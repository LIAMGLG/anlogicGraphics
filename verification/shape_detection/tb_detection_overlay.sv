`timescale 1ns/1ps
module tb_detection_overlay;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,enable=1,valid=0,user=0,last=0,overflow=0;
    reg [255:0] boxes=0;
    reg [3:0] held=0;
    reg [2:0] count=1;
    reg [95:0] data=0;
    wire [95:0] result;
    wire ov,ou,ol;
    detection_overlay_rgb96 #(.IMG_WIDTH(384),.COORDINATES(1)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_enable(enable),.I_boxes(boxes),.I_count(count),.I_overflow(overflow),
        .I_held(held),
        .I_tdata(data),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
        .O_tdata(result),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol));
    `include "verification/shape_detection/golden_font.vh"
    reg [95:0] e0=0,e1=0,e2=0,wanted;
    reg v0=0,v1=0,v2=0,u0=0,u1=0,u2=0,l0=0,l1=0,l2=0;
    integer frame,row,beat,lane,px,idx,checks=0;
    reg [127:0] text;
    reg [15:0] bits;
    reg [7:0] ch;
    reg [23:0] pixel;
    reg [63:0] box_record;
    always @(posedge clk) begin
        if(!rst) begin v0<=0;v1<=0;v2<=0;u0<=0;u1<=0;u2<=0;l0<=0;l1<=0;l2<=0; end
        else begin
            e0<=wanted;e1<=e0;e2<=e1;v0<=valid;v1<=v0;v2<=v1;u0<=user;u1<=u0;u2<=u1;l0<=last;l1<=l0;l2<=l1;
            #1;
            if(ov!==v2 || ou!==u2 || ol!==l2) $fatal(1,"Overlay three-cycle controls");
            if(v2) begin
                checks=checks+1;
                if(result!==e2) $fatal(1,"Overlay pixels frame=%0d row=%0d beat=%0d got=%h expected=%h",frame,row,beat,result,e2);
            end
        end
    end
    initial begin
        wanted=0;
        box_record=0;box_record[63]=1;box_record[62:61]=1;box_record[60:59]=1;
        box_record[58:48]=300;box_record[47:38]=200;box_record[37:27]=340;box_record[26:17]=240;
        box_record[16:0]=100;
        repeat(4) @(negedge clk);rst=1;
        for(frame=0;frame<6;frame=frame+1) begin
            enable=frame!=1;overflow=frame==2;boxes=frame==0 ? box_record : 256'd0;count=frame==0 ? 1 : 0;
            held=0;
            // Four fully overlapping targets exercise object-1 priority and all legend rows.
            if(frame==3) begin
                boxes={box_record,box_record,box_record,box_record};count=4;
                boxes[64+62 -:2]=2; boxes[128+62 -:2]=3;
                boxes[128+60 -:2]=3;
            end
            // Sparse fixed slot 3, held then reacquired. Counts exclude held boxes.
            if(frame>=4) begin
                boxes=0;boxes[128 +:64]=box_record;
                held=frame==4 ? 4'b0100 : 0;
                overflow=0;count=frame==4 ? 0 : 1;
            end
            for(row=0;row<256;row=row+1) for(beat=0;beat<96;beat=beat+1) begin
                @(negedge clk);valid=1;user=row==0 && beat==0;last=beat==95;
                data={24'h123456,24'h234567,24'h345678,24'h456789};wanted=data;
                // New results and key events mid-frame must wait for next SOF.
                if(row==180) begin boxes=0;held=0;count=0;enable=~enable;overflow=1; end
                for(lane=0;lane<4;lane=lane+1) begin
                    px=beat*4+lane;pixel=data[95-lane*24 -:24];
                    if(frame!=1) begin
                        if((frame==0 || frame==3) && px>=300 && px<=340 && row>=200 && row<=240 &&
                            (px<302 || px>338 || row<202 || row>238)) pixel=24'hff4040;
                        if((frame==0 || frame==3) && px>=300 && px<316 && row>=200 && row<216) begin
                            bits=golden_font("1",row-200);
                            pixel=bits[15-(px-300)] ? 24'hffffff : 24'h000000;
                        end
                        text=frame==0 ? "N:1 R:1 G:0     " : "LABEL OVERFLOW  ";
                        if(frame==3) text="N:4 R:2 G:1     ";
                        if(px>=16 && px<272 && row>=64 && row<80) begin
                            idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,row-64);
                            pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                        end
                        if(frame==0 && px>=16 && px<272 && row>=96 && row<112) begin
                            text="1 RED   RECT    ";idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,row-96);
                            pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                        end
                        if(frame==3 && px>=16 && px<272 && row>=96 && row<160) begin
                            case((row-96)/16)
                                0:text="1 RED   RECT    ";
                                1:text="2 GREEN RECT    ";
                                2:text="3 BLUE  TRIANGLE";
                                3:text="4 RED   RECT    ";
                            endcase
                            idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,(row-96)%16);
                            pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                        end
                        if(frame>=4) begin
                            if(px>=300 && px<=340 && row>=200 && row<=240 &&
                                (px<302 || px>338 || row<202 || row>238) &&
                                (frame==5 || ((px/8)%2==(row/8)%2)))
                                pixel=frame==4 ? 24'h909090 : 24'hff4040;
                            if(px>=300 && px<316 && row>=200 && row<216) begin
                                bits=golden_font("3",row-200);
                                pixel=bits[15-(px-300)] ? 24'hffffff : 24'h000000;
                            end
                            if(px>=16 && px<272 && row>=64 && row<80) begin
                                text=frame==4 ? "N:0 R:0 G:0     " : "N:1 R:1 G:0     ";
                                idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,row-64);
                                pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                            end
                            if(px>=16 && px<272 && row>=128 && row<144) begin
                                text=frame==4 ? "3 RED   WAIT    " : "3 RED   RECT    ";
                                idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,row-128);
                                pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                            end
                            if(frame>=4 && px>=16 && px<272 && row>=208 && row<224) begin
                                text="3 X:0320 Y:0220 ";
                                idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,row-208);
                                pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                            end
                        end
                    end
                    if((frame==0 || frame==3) && px>=16 && px<272 && row>=176 &&
                       row<(frame==0 ? 192 : 240)) begin
                        case((row-176)/16)
                            0:text="1 X:0320 Y:0220 ";
                            1:text="2 X:0320 Y:0220 ";
                            2:text="3 X:0320 Y:0220 ";
                            3:text="4 X:0320 Y:0220 ";
                        endcase
                        idx=(px-16)/16;ch=text[127-idx*8 -:8];bits=golden_font(ch,(row-176)%16);
                        pixel=bits[15-(px-16)%16] ? 24'hfff200 : 24'h000000;
                    end
                    wanted[95-lane*24 -:24]=pixel;
                end
            end
        end
        @(negedge clk);valid=0;user=0;last=0;repeat(4) @(negedge clk);
        if(checks!=6*256*96) $fatal(1,"Overlay pixel count");
        $display("PASS: overlay per-pixel boxes, fixed/sparse number tags, WAIT, gray dashed held boxes, measured counts, center coordinates, overflow, SOF snapshots, disable and three-cycle controls");
        $finish;
    end
endmodule
