`timescale 1ns/1ps
// Uses the demosaic/AWB substitutes in tb_isp_modes.sv. Full 1280x720 frame.
module tb_detection_isp;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0,key=1;
    reg [39:0] data=0;
    integer row,beat,xx,yy,waits,scene;
    reg [23:0] rgb;
    wire [127:0] outdata;
    wire outvalid,outuser;
    function automatic [15:0] expected_decimal(input integer value);
        begin
            expected_decimal[15:12]=value/1000;expected_decimal[11:8]=(value/100)%10;
            expected_decimal[7:4]=(value/10)%10;expected_decimal[3:0]=value%10;
        end
    endfunction
    task check_coordinates;
        reg [63:0] r;
        integer slot,center_x,center_y;
        begin
            repeat(105) @(negedge clk);
            if(!dut.u_detection_overlay.coordinates_ready) $fatal(1,"ISP coordinate conversion incomplete");
            for(slot=0;slot<4;slot=slot+1) begin
                r=dut.detected_boxes[slot*64 +:64];
                center_x=(int'(r[58:48])+int'(r[37:27]))/2;
                center_y=(int'(r[47:38])+int'(r[26:17]))/2;
                if(dut.u_detection_overlay.coordinates[slot*32 +:16]!==expected_decimal(center_x) ||
                    dut.u_detection_overlay.coordinates[slot*32+16 +:16]!==expected_decimal(center_y))
                    $fatal(1,"ISP fixed-slot/held coordinate snapshot");
            end
        end
    endtask
    isp_top dut (.axi4s_video_aclk(clk),.I_rst_n(rst),.I_key_bin(1'b1),.I_key_detect(key),
        .I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tdest(10'd0),
        .O_tready(1'b1),.O_tdata(outdata),.O_tlast(),.O_tuser(outuser),.O_tvalid(outvalid),.I_tready());
    initial begin
        repeat(5) @(negedge clk);rst=1;
        // Integer-coordinate synthetic shapes, independent of display mode.
        for(row=0;row<720;row=row+1) for(beat=0;beat<320;beat=beat+1) begin
            @(negedge clk);valid=1;user=row==0 && beat==0;last=beat==319;
            rgb=0;xx=beat;yy=row/4;
            if(xx>=100 && xx<124 && yy>=75 && yy<99) rgb=24'he02010;
            if(xx>=200 && xx<220 && yy>=100 && yy<120) rgb=24'h10e020;
            if((xx-260)*(xx-260)+(yy-60)*(yy-60)<=256) rgb=24'h2010e0;
            if(yy>=120 && yy<=150 && (xx-55)*2<=yy-120 && (xx-55)*2>=-(yy-120)) rgb=24'he02010;
            data={16'd0,rgb};
        end
        @(negedge clk);valid=0;user=0;last=0;
        waits=0;
        while(!dut.u_target_tracker.O_update && waits<1500000) begin @(posedge clk);#1;waits=waits+1;end
        if(waits==1500000 || dut.detected_count!=3 || dut.detected_overflow) $fatal(1,"Full ISP detection count (blue ignored)");
        if(dut.detected_boxes[64+60 -:2]!=3 || dut.detected_boxes[64+62 -:2]!=1)
            $fatal(1,"Full ISP red triangle classification");
        if(dut.detected_boxes[62:61]!=1 || dut.detected_boxes[60:59]!=1)
            $fatal(1,"Full ISP largest red rectangle color/shape");
        for(integer obj=0;obj<3;obj=obj+1)
            if(dut.detected_boxes[obj*64+61 +:2]==3) $fatal(1,"Blue must not be detected");
        if(dut.detected_boxes[58:48]!=400 || dut.detected_boxes[37:27]!=495 ||
           dut.detected_boxes[47:38]!=300 || dut.detected_boxes[26:17]!=395)
            $fatal(1,"Full ISP scale mapping");
        // A publication between frames must become visible at the next OSD SOF.
        @(negedge clk);valid=1;user=1;data=0;
        @(negedge clk);valid=0;user=0;
        repeat(10) @(negedge clk);
        if(dut.u_detection_overlay.count!=3 || dut.u_detection_overlay.boxes!==dut.detected_boxes)
            $fatal(1,"Result snapshot integration");
        if(!dut.u_detection_mask_osd.ready || !dut.u_detection_overlay.converting)
            $fatal(1,"Mask/coordinate conversion start integration");
        if(dut.raw_debug[7:0]!=8'h40 || dut.raw_debug[15:8]!=8'h30)
            $fatal(1,"Contour diagnostic metadata");
        check_coordinates();
        // Three more actual 720p captures: move/rerank, lose rectangle, recover.
        // Green grows from third largest to largest; IDs must stay 1/2/3.
        for(scene=0;scene<3;scene=scene+1) begin
            for(row=0;row<720;row=row+1) for(beat=0;beat<320;beat=beat+1) begin
                @(negedge clk);valid=1;user=row==0 && beat==0;last=beat==319;
                rgb=0;xx=beat;yy=row/4;
                if(scene!=1 && xx>=104 && xx<128 && yy>=77 && yy<101) rgb=24'he02010;
                if(xx>=198 && xx<226 && yy>=96 && yy<124) rgb=24'h10e020;
                if(yy>=120 && yy<=150 && (xx-59)*2<=yy-120 && (xx-59)*2>=-(yy-120)) rgb=24'he02010;
                data={16'd0,rgb};
            end
            @(negedge clk);valid=0;user=0;last=0;waits=0;
            while(!dut.u_target_tracker.O_update && waits<1500000) begin @(posedge clk);#1;waits=waits+1;end
            if(waits==1500000 || dut.detected_overflow || dut.raw_detected_boxes[62:61]!=2)
                $fatal(1,"Moving ISP completion/ranking");
            if(dut.detected_count!=(scene==1 ? 2 : 3) || dut.detected_held!=(scene==1 ? 4'b0001 : 0))
                $fatal(1,"Moving ISP measured count/held state");
            if(dut.detected_boxes[58:48]!=416 || dut.detected_boxes[64+58 -:11]!=176 ||
                dut.detected_boxes[128+58 -:11]!=792 || dut.detected_boxes[128+62 -:2]!=2)
                $fatal(1,"Moving ISP fixed-slot coordinates");
            if(scene==1) begin
                if(dut.display_debug!=={8'd0,dut.raw_debug[7:0],dut.raw_debug[15:8],8'd0})
                    $fatal(1,"Missing ISP diagnostic remap");
            end else if(dut.display_debug!=={8'd0,dut.raw_debug[7:0],dut.raw_debug[23:16],dut.raw_debug[15:8]})
                $fatal(1,"Ranked ISP diagnostic remap");
            @(negedge clk);valid=1;user=1;data=0;
            @(negedge clk);valid=0;user=0;repeat(10) @(negedge clk);
            if(dut.u_detection_overlay.boxes!==dut.detected_boxes ||
                dut.u_detection_overlay.held!==dut.detected_held ||
                !dut.u_detection_overlay.converting || !dut.u_detection_mask_osd.ready)
                $fatal(1,"Moving ISP SOF publication");
            check_coordinates();
        end
        // Exercise the actual fourth-key debounce and frame-committed enable.
        key=0;
        repeat(400010) @(negedge clk);
        if(dut.detection_enabled!==0) $fatal(1,"k4 toggle");
        repeat(20) @(negedge clk);
        if(dut.detection_enabled!==0) $fatal(1,"Held key repeated");
        key=1;
        @(negedge clk);valid=1;user=1;
        @(negedge clk);valid=0;user=0;
        repeat(10) @(negedge clk);
        if(dut.u_detection_overlay.enabled!==0) $fatal(1,"k4 frame commit");
        if(dut.u_detection_mask_osd.enabled!==0) $fatal(1,"k4 mask frame commit");
        $display("PASS: four 720p ISP captures, moving fixed IDs, rank changes, miss/recovery, center coordinates including held tracks, MASK/result SOF snapshot and k4 debounce/held-key/frame commit");
        $finish;
    end
    initial begin #100000000;$fatal(1,"ISP detection timeout");end
endmodule
