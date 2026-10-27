`timescale 1ns/1ps
// Uses upstream substitutes from tb_isp_modes; checks ISP integration only.
module tb_imaging_hold;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,user=0,adjust=0,inhibit=0;
    isp_top dut(.axi4s_video_aclk(clk),.I_rst_n(rst),.I_key_bin(1'b1),.I_key_detect(1'b1),
        .I_motion_inhibit(inhibit),.I_camera_adjust(adjust),.I_exposure_status(30'h11660100),
        .I_tlast(1'b0),.I_tuser(user),.I_tdata(40'd0),.I_tvalid(1'b0),.I_tdest(10'd0),.O_tready(1'b1));
    task sof;
        begin
            @(negedge clk);user=1;
            @(negedge clk);user=0;
            repeat(6) @(negedge clk);
        end
    endtask
    integer i;
    initial begin
        force dut.video_mode_d2=3'd5;
        repeat(4) @(negedge clk);rst=1;
        @(negedge clk);adjust=1;
        @(negedge clk);adjust=0;
        if(dut.imaging_hold!=4 || dut.u_motion_detect.I_enable) $fatal(1,"AE event suppression");
        for(i=3;i>=0;i=i-1) begin
            sof();if(dut.imaging_hold!=i) $fatal(1,"hold duration");
        end
        if(!dut.u_motion_detect.I_enable) $fatal(1,"motion enable did not recover");
        force dut.awb_color_change=1;
        @(negedge clk);release dut.awb_color_change;
        if(dut.imaging_hold!=4) $fatal(1,"AWB event suppression");
        inhibit=1;repeat(6) @(negedge clk);
        repeat(4) sof();
        if(dut.u_motion_detect.I_enable || dut.motion_settle!=12) $fatal(1,"SW1 suppression lost");
        $display("PASS: AE/AWB four-SOF motion suppression preserves SW1 inhibit");$finish;
    end
    initial begin #10000;$fatal(1,"timeout");end
endmodule
