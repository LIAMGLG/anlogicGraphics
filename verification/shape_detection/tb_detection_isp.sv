`timescale 1ns/1ps
// Uses the demosaic/AWB substitutes in tb_isp_modes.sv. Full 1280x720 frame.
module tb_detection_isp;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0,key=1;
    reg [39:0] data=0;
    integer row,beat,xx,yy,waits;
    reg [23:0] rgb;
    wire [127:0] outdata;
    wire outvalid,outuser;
    isp_top dut (.axi4s_video_aclk(clk),.I_rst_n(rst),.I_key_bin(1'b1),.I_adjust_enable(1'b0),
        .I_key_threshold(1'b1),.I_key_edge(1'b1),.I_key_detect(key),
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
        while(!dut.u_detection_stabilizer.O_update && waits<1500000) begin @(posedge clk);#1;waits=waits+1;end
        if(waits==1500000 || dut.detected_count!=4 || dut.detected_overflow) $fatal(1,"Full ISP detection count");
        if(dut.detected_boxes[128+60 -:2]!=3 || dut.detected_boxes[128+62 -:2]!=1)
            $fatal(1,"Full ISP red triangle classification");
        if(dut.detected_boxes[62:61]!=3 || dut.detected_boxes[60:59]!=2)
            $fatal(1,"Full ISP largest disk color/shape");
        if(dut.detected_boxes[58:48]!=976 || dut.detected_boxes[37:27]!=1107 ||
           dut.detected_boxes[47:38]!=176 || dut.detected_boxes[26:17]!=307)
            $fatal(1,"Full ISP scale mapping");
        // A publication between frames must become visible at the next OSD SOF.
        @(negedge clk);valid=1;user=1;data=0;
        @(negedge clk);valid=0;user=0;
        repeat(10) @(negedge clk);
        if(dut.u_detection_overlay.count!=4 || dut.u_detection_overlay.boxes!==dut.detected_boxes)
            $fatal(1,"Result snapshot integration");
        if(!dut.u_detection_mask_osd.ready || dut.u_detection_overlay.debug_info!==dut.raw_debug)
            $fatal(1,"Mask/debug publication integration");
        if(dut.raw_debug[3:0]!=0 || dut.raw_debug[7:4]<5 || dut.raw_debug[23:16]!=8'h30)
            $fatal(1,"Contour diagnostic metadata");
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
        $display("PASS: full 720p ISP colors/shapes, scaling, result SOF snapshot and k4 debounce/held-key/frame commit");
        $finish;
    end
    initial begin #30000000;$fatal(1,"ISP detection timeout");end
endmodule
