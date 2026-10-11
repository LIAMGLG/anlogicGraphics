module latency_system #(parameter FRAME_WORDS=172800)(
    input wire I_rst_n,I_sys_clk,I_csi_clk,I_ddr_clk,I_pixel_clk,
    input wire I_csi_start,I_raw_start,I_isp_start,I_overflow,
    input wire I_write_start,input wire [1:0] I_write_slot,
    input wire I_commit,input wire [24:0] I_commit_addr,
    input wire I_read_start,input wire [1:0] I_read_slot,
    input wire I_underflow,
    input wire I_vs,I_hs,I_de,input wire [23:0] I_rgb,
    output wire O_vs,O_hs,O_de,output wire [23:0] O_rgb
);
    wire [31:0] sys_us,csi_us,pixel_us,latest_id,pixel_latest_id;
    wire tick,time_csi_error,time_pixel_error,id_error;
    wire time_csi_busy,time_pixel_busy,time_csi_valid,time_pixel_valid;
    reg csi_time_seen,csi_time_ready,pixel_time_seen,pixel_time_ready;
    latency_timebase u_timebase(.I_clk(I_sys_clk),.I_rst_n(I_rst_n),.O_us(sys_us),.O_tick(tick));
    // Handshake stable timestamp snapshots every microsecond, instead of
    // independently synchronizing the bits of a continuously changing bus.
    latency_cdc #(.WIDTH(32)) u_csi_time(
        .I_rst_n(I_rst_n),.I_src_clk(I_sys_clk),.I_send(tick && !time_csi_busy),.I_data(sys_us),
        .O_busy(time_csi_busy),.O_error(time_csi_error),.I_dst_clk(I_csi_clk),.O_valid(time_csi_valid),.O_data(csi_us));
    latency_cdc #(.WIDTH(32)) u_pixel_time(
        .I_rst_n(I_rst_n),.I_src_clk(I_sys_clk),.I_send(tick && !time_pixel_busy),.I_data(sys_us),
        .O_busy(time_pixel_busy),.O_error(time_pixel_error),.I_dst_clk(I_pixel_clk),.O_valid(time_pixel_valid),.O_data(pixel_us));
    // CSI clock may be dormant during camera configuration. Busy means wait,
    // not a fatal overrun. Discard the first (possibly old) timestamp snapshot;
    // only associate frames after a second, newly published snapshot arrives.
    always @(posedge I_csi_clk or negedge I_rst_n)
        if(!I_rst_n) begin csi_time_seen<=0;csi_time_ready<=0;end
        else if(time_csi_valid) begin csi_time_seen<=1;if(csi_time_seen) csi_time_ready<=1;end
    always @(posedge I_pixel_clk or negedge I_rst_n)
        if(!I_rst_n) begin pixel_time_seen<=0;pixel_time_ready<=0;end
        else if(time_pixel_valid) begin pixel_time_seen<=1;if(pixel_time_seen) pixel_time_ready<=1;end
    latency_cdc #(.WIDTH(32)) u_frame_id(
        .I_rst_n(I_rst_n),.I_src_clk(I_csi_clk),.I_send(I_csi_start),.I_data(latest_id+32'd1),
        .O_busy(),.O_error(id_error),.I_dst_clk(I_pixel_clk),.O_valid(),.O_data(pixel_latest_id));
    wire [64:0] capture_meta,ddr_meta,selected_meta,pixel_meta;
    wire capture_error,capture_busy,capture_cdc_error,ddr_meta_valid;
    wire publish,slot_error,read_bad,read_busy,read_cdc_error,pixel_meta_valid;
    latency_capture u_capture(
        .I_clk(I_csi_clk),.I_rst_n(I_rst_n),.I_csi_start(I_csi_start),
        .I_raw_start(I_raw_start),.I_isp_start(I_isp_start),.I_us(csi_us),.I_time_valid(csi_time_ready),
        .O_latest_id(latest_id),.O_meta(capture_meta),.O_error(capture_error));
    latency_cdc u_capture_mailbox(
        .I_rst_n(I_rst_n),.I_src_clk(I_csi_clk),.I_send(I_isp_start),.I_data(capture_meta),
        .O_busy(capture_busy),.O_error(capture_cdc_error),.I_dst_clk(I_ddr_clk),
        .O_valid(ddr_meta_valid),.O_data(ddr_meta));
    latency_slots #(.FRAME_WORDS(FRAME_WORDS)) u_slots(
        .I_clk(I_ddr_clk),.I_rst_n(I_rst_n),.I_meta_valid(ddr_meta_valid),.I_meta(ddr_meta),
        .I_write_start(I_write_start),.I_write_slot(I_write_slot),
        .I_commit(I_commit),.I_commit_addr(I_commit_addr),
        .I_read_start(I_read_start),.I_read_slot(I_read_slot),
        .O_publish(publish),.O_read_meta(selected_meta),.O_read_bad(read_bad),.O_error(slot_error));
    latency_cdc u_display_mailbox(
        .I_rst_n(I_rst_n),.I_src_clk(I_ddr_clk),.I_send(publish),.I_data(selected_meta),
        .O_busy(read_busy),.O_error(read_cdc_error),.I_dst_clk(I_pixel_clk),
        .O_valid(pixel_meta_valid),.O_data(pixel_meta));
    (* async_reg="true" *) reg [8:0] faults1,faults2;
    (* async_reg="true" *) reg csi_ready1,csi_ready2;
    always @(posedge I_pixel_clk or negedge I_rst_n)
        if(!I_rst_n) begin faults1<=0;faults2<=0;csi_ready1<=0;csi_ready2<=0;end
        else begin
            csi_ready1<=csi_time_ready;csi_ready2<=csi_ready1;
            faults1<={time_csi_error,time_pixel_error,id_error,I_overflow,capture_error,capture_cdc_error,slot_error,read_cdc_error,read_bad};
            faults2<=faults1;
        end
    (* keep="true" *) wire measure_valid;
    (* keep="true" *) wire [31:0] latency_us,frame_age,display_id;
    wire [10:0] wait_reason={!pixel_time_ready || !csi_ready2,I_underflow,faults2};
    latency_osd u_osd(
        .I_clk(I_pixel_clk),.I_rst_n(I_rst_n),.I_us(pixel_us),.I_latest_id(pixel_latest_id),
        .I_meta_valid(pixel_meta_valid),.I_meta(pixel_meta),.I_bad(|wait_reason),.I_reason(wait_reason),
        .I_vs(I_vs),.I_hs(I_hs),.I_de(I_de),.I_rgb(I_rgb),
        .O_vs(O_vs),.O_hs(O_hs),.O_de(O_de),.O_rgb(O_rgb),
        .O_measure_valid(measure_valid),.O_latency_us(latency_us),.O_age(frame_age),.O_display_id(display_id));
endmodule
