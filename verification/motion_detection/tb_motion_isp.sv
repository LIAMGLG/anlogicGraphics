`timescale 1ns/1ps
// Uses only the demosaic/AWB substitutes in tb_isp_modes.sv. All new motion
// logic and the display pipeline are actual RTL.
module tb_motion_isp;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,u=0,l=0;
    reg [39:0] data=0;
    reg [2:0] requested=0;
    isp_top dut(.axi4s_video_aclk(clk),.I_rst_n(rst),.I_key_bin(1'b1),.I_key_detect(1'b1),
        .I_tlast(l),.I_tuser(u),.I_tdata(data),.I_tvalid(v),.I_tdest(10'd0),
        .O_tready(1'b1),.O_tdata(),.O_tlast(),.O_tuser(),.O_tvalid(),.I_tready());
    reg [95:0] rgb_ref[0:3];
    integer i,f,y,x,frame_out=-1,checked=0;
    reg [2:0] out_mode;
    reg [95:0] wanted;
    reg [143:0] expected_map;
    always @(posedge clk) if(rst) begin
        for(i=3;i>0;i=i-1) rgb_ref[i]<=rgb_ref[i-1];
        rgb_ref[0]<={4{data[23:0]}};
        #1;
        if(dut.edge_O_tvalid && dut.motion_rgb_d4!==rgb_ref[3]) $fatal(1,"AWB motion alignment");
        if(dut.motion_valid!==dut.detection_valid || dut.motion_user!==dut.detection_user ||
           dut.motion_last!==dut.detection_last) $fatal(1,"parallel overlay latency");
        if(dut.detection_user) begin
            frame_out=frame_out+1;
            out_mode=(frame_out==0 || frame_out==5) ? 0 : 5;
            if(dut.motion_selected!==(out_mode==5)) $fatal(1,"mode output frame %0d",frame_out);
            if(out_mode==5 && (dut.u_detection_overlay.enabled || dut.u_detection_mask_osd.enabled))
                $fatal(1,"color overlays visible in motion");
            expected_map=0;
            if(frame_out==4) expected_map[0]=1;
            if(out_mode==5 && dut.u_motion_overlay.regions!==expected_map)
                $fatal(1,"ISP region frame %0d got %h",frame_out,dut.u_motion_overlay.regions);
            if(frame_out==4 && dut.motion_data[95:72]!==24'hfff200) $fatal(1,"yellow region missing");
            checked=checked+1;
        end
    end
    initial begin
        force dut.u_key_video_mode.requested_mode=requested;
        repeat(4) @(negedge clk);rst=1;
        for(f=0;f<8;f=f+1) begin
            requested=(f==0 || f==5) ? 0 : 5;
            for(y=0;y<720;y=y+1) for(x=0;x<320;x=x+1) begin
                @(negedge clk);v=1;u=y==0 && x==0;l=x==319;
                data=40'h00282828;
                if((f==2 || f==4) && y<80 && x<20) data=40'h00646464;
            end
        end
        @(negedge clk);v=0;u=0;l=0;repeat(30) @(negedge clk);
        if(checked!=8) $fatal(1,"frame count %0d",checked);
        $display("PASS: motion ISP 720p AWB alignment, color overlay suppression, yellow regions, exit/re-entry, adjacent SOF and unchanged latency");
        $finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
