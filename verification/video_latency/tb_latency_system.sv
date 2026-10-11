`timescale 1ns/1ps
// Different, non-harmonic clock periods. Exercise the complete new subsystem
// with the REAL video_in/video_out frame-pointer blocks (FIFO data is stubbed).
module tb_latency_system #(parameter STARTUP_DELAY_NS=0);
    reg sys=0,csi=0,ddr=0,pixel=0,rst=0;
    reg csi_enable=(STARTUP_DELAY_NS==0);
    always #10 sys=~sys;
    always #7 if(csi_enable) csi=~csi;else csi=0;
    always #5 ddr=~ddr;
    always #6.73 pixel=~pixel;
    reg cs=0,raw=0,isp=0,vs=0,de=0;
    wire ws,rs,overflow,underflow;
    wire [1:0] wp,rp,readptr;
    wire [24:0] actual_read_addr;
    reg commit=0;reg [24:0] addr=0;
    wire ovs,ohs,ode;wire [23:0] orgb;
    video_in vi(.I_rst_n(rst),.I_camera_clk(csi),.I_camera_frame_start(isp),
        .I_camera_valid(1'b0),.I_camera_data(128'd0),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(),.O_video_out_rp(readptr),.O_latency_start(ws),
        .O_latency_slot(wp),.O_latency_overflow(overflow),
        .O_ddr_user_wr_en(),.O_ddr_user_addr(),.O_ddr_user_wr_data(),.I_ddr_user_ready(1'b0));
    video_out vo(.I_rst_n(rst),.I_ddr_clk(ddr),.O_video_out_rd_busy(),
        .I_video_in_wr_busy(1'b0),.I_video_out_rp(readptr),
        .O_ddr_user_rd_en(),.O_ddr_user_addr(actual_read_addr),.I_ddr_user_ready(1'b0),
        .I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),
        .I_dsi_clk(pixel),.I_video_vsync(~vs),.I_video_rd_en(1'b0),.O_vdieo_data(),
        .O_latency_start(rs),.O_latency_slot(rp),.O_latency_underflow(underflow));
    latency_system #(.FRAME_WORDS(4)) dut(
        .I_rst_n(rst),.I_sys_clk(sys),.I_csi_clk(csi),.I_ddr_clk(ddr),.I_pixel_clk(pixel),
        .I_csi_start(cs),.I_raw_start(raw),.I_isp_start(isp),.I_overflow(overflow),
        .I_write_start(ws),.I_write_slot(wp),.I_commit(commit),.I_commit_addr(addr),
        .I_read_start(rs),.I_read_slot(rp),.I_underflow(underflow),
        .I_vs(vs),.I_hs(1'b0),.I_de(de),.I_rgb(24'h345678),
        .O_vs(ovs),.O_hs(ohs),.O_de(ode),.O_rgb(orgb));
    function [24:0] base(input integer slot);
        case(slot) 0:base=0;1:base=7000000;2:base=14000000;default:base=21000000;endcase
    endfunction
    realtime capture_time[1:8];
    integer observed_wp;
    always @(posedge ddr) if(ws) observed_wp=wp;
    task acquire(input integer id);
        begin
            @(negedge csi);cs=1;@(posedge csi);capture_time[id]=$realtime;
            @(negedge csi);cs=0;raw=1;@(negedge csi);raw=0;
            repeat(10) @(negedge csi);
            isp=1;@(negedge csi);isp=0;
            #1000;
            if(observed_wp!=(id-1)%4) $fatal(1,"pre-increment write slot mismatch");
            if(readptr!==2'(((id-1)+2)%4)) $fatal(1,"real read pointer mismatch");
            for(integer w=0;w<4;w=w+1) begin
                @(negedge ddr);commit=1;addr=base((id-1)%4)+w*8;
                @(negedge ddr);commit=0;
            end
            #9000;
        end
    endtask
    realtime first_pixel_time;
    integer expected_us;
    task display(input integer id,input integer cap_id);
        begin
            @(negedge pixel);de=0;vs=1;
            repeat(5) @(negedge pixel);
            vs=0;
            repeat(30) @(negedge pixel);
            if(actual_read_addr!==base((id-1)%4)) $fatal(1,"metadata/address selection mismatch");
            de=1;@(posedge pixel);first_pixel_time=$realtime;#1;
            expected_us=(first_pixel_time-capture_time[id])/1000;
            if(!dut.measure_valid || dut.display_id!=id || dut.frame_age!=cap_id-id)
                $fatal(1,"integrated frame association id=%0d valid=%b actual=%0d age=%0d faults=%b",id,dut.measure_valid,dut.display_id,dut.frame_age,dut.faults2);
            if(dut.latency_us+2<expected_us || dut.latency_us>expected_us+2)
                $fatal(1,"timestamp disagrees with wall-clock reference actual=%0d expected=%0d",dut.latency_us,expected_us);
            repeat(40) @(negedge pixel);
            de=0;
        end
    endtask
    initial begin
        #101;rst=1;
        if(STARTUP_DELAY_NS!=0) begin
            #(STARTUP_DELAY_NS);
            if(dut.time_csi_error) $fatal(1,"dormant CSI clock permanently poisoned timestamp mailbox");
            csi_enable=1;
        end
        #3000;
        for(integer id=1;id<=8;id=id+1) begin
            acquire(id);
            if(id>=3) begin display(id-2,id);display(id-2,id);end
        end
        if(dut.capture_error || dut.slot_error || dut.capture_cdc_error || dut.read_cdc_error ||
           dut.time_csi_error || dut.time_pixel_error || dut.id_error)
            $fatal(1,"unexpected integrated subsystem fault");
        if(STARTUP_DELAY_NS!=0) $display("PASS: delayed CSI clock startup recovers timestamps and valid latency without reset");
        $display("PASS: integrated latency with real four-slot pointer logic, asynchronous clocks, repeated display and common-time reference");
        $finish;
    end
    initial begin #1000000;$fatal(1,"integrated timeout");end
endmodule

// Only the vendor FIFO storage is replaced; real frame/address control remains.
module w128_d512_fifo(
    input wire rst,clkw,we,input wire [127:0] di,
    output wire afull,full_flag,output wire [8:0] wrusedw,
    input wire clkr,re,output wire [127:0] dout,output wire [8:0] rdusedw,
    output wire valid,empty_flag,aempty
);
    assign afull=0;assign full_flag=0;assign wrusedw=0;assign dout=0;
    assign rdusedw=0;assign valid=0;assign empty_flag=1;assign aempty=1;
endmodule
