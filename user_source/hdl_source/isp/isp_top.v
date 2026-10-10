module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_key_bin		,   // key1: normal / binary / edge / cartoon / gray
    input wire      I_key_detect,    // k4: toggle detection overlays
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 

  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 
  wire [95:0] gain_data;
  wire gain_valid,gain_user,gain_last;
  wire [95:0] saturation_data;
  wire saturation_valid,saturation_user,saturation_last;
  wire [2:0] saturation_mode;

  wire         display_user_128;  //synthesis keep
  wire         display_valid_128;  //synthesis keep
  wire [127:0] display_data_128;  //synthesis keep

  wire         bin_O_tlast;
  wire         bin_O_tuser;
  wire [ 95:0] bin_O_tdata;
  wire         bin_O_tvalid;

  wire [2:0] video_mode;
  wire [95:0] grayscale_data;
  wire [95:0] edge_O_tdata;
  wire [95:0] cartoon_O_tdata;
  wire edge_O_tlast, edge_O_tuser, edge_O_tvalid;
  wire [95:0] osd_data;
  wire osd_last, osd_user, osd_valid;
  wire [95:0] detection_data;
  wire detection_last, detection_user, detection_valid;
  wire [95:0] logo_data;
  wire logo_last,logo_user,logo_valid;
  wire reduced_valid;
  wire [1:0] reduced_color;
  wire [8:0] reduced_x;
  wire [7:0] reduced_y;
  wire [255:0] detected_boxes;
  wire [2:0] detected_count;
  wire detected_overflow;
  wire [255:0] raw_detected_boxes;
  wire [2:0] raw_detected_count;
  wire raw_detected_overflow,raw_detected_update;
  wire capture_valid,capture_done,stable_update;
  wire [31:0] raw_debug;
  reg [31:0] published_debug;
  wire [31:0] display_debug=stable_update ? raw_debug : published_debug;
  wire [95:0] mask_osd_data;
  wire mask_osd_valid,mask_osd_user,mask_osd_last;
  wire detection_key_pressed;
  reg detection_enabled;
  reg [95:0] normal_data_d1, binary_data_d1, normal_data_d2, binary_data_d2;
  reg [2:0] video_mode_d1, video_mode_d2;
  wire [95:0] processed_data = (video_mode_d2 == 3'd4) ? grayscale_data :
                               (video_mode_d2 == 3'd3) ? cartoon_O_tdata :
                               (video_mode_d2 == 3'd2) ? edge_O_tdata :
                               (video_mode_d2 == 3'd1) ? binary_data_d2 : normal_data_d2;
  assign awb_O_tready = O_tready;
  assign O_tdata  = display_data_128;
  assign O_tlast  = logo_last;
  assign O_tuser  = display_user_128    ;
  assign O_tvalid = display_valid_128   ;

demosaic #(
    .IMG_HEIGHT          (720 ),  // 图像高度
    .IMG_WIDTH           (1280),  // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

color_gain_rgb96 u_color_gain (
    .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
    .I_tdata(awb_O_tdata),.I_tvalid(awb_O_tvalid),.I_tuser(awb_O_tuser),.I_tlast(awb_O_tlast),
    .O_tdata(gain_data),.O_tvalid(gain_valid),.O_tuser(gain_user),.O_tlast(gain_last)
);

// Post-AWB RGB gains feed display algorithms; detection uses ungained AWB RGB.
binary_threshold_96 #(
    .THRESHOLD(8'd64), .DYNAMIC_THRESHOLD(0)
) u_binary_threshold_96 (
    .I_threshold(8'd64),
    .I_tlast (gain_last),
    .I_tuser (gain_user),
    .I_tdata (gain_data),
    .I_tvalid(gain_valid),
    .O_tlast (bin_O_tlast),
    .O_tuser (bin_O_tuser),
    .O_tdata (bin_O_tdata),
    .O_tvalid(bin_O_tvalid)
);

// All paths run continuously. Keep normal/binary data and mode aligned
// with the edge module's two-cycle latency, including the first frame beat.
edge_detect_96 #(
    .IMG_WIDTH(1280), .IMG_HEIGHT(720), .EDGE_TH(11'd60), .DYNAMIC_THRESHOLD(0)
) u_edge_detect_96 (
    .I_edge_th(11'd60),
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_tlast(gain_last), .I_tuser(gain_user),
    .I_tdata(gain_data), .I_tvalid(gain_valid),
    .I_tready(), .O_tready(awb_O_tready),
    .O_tlast(edge_O_tlast), .O_tuser(edge_O_tuser),
    .O_tdata(edge_O_tdata), .O_tvalid(edge_O_tvalid)
);

// Reuse the edge mask and align posterized colors to its window centers.
cartoon_96 #(.IMG_WIDTH(1280), .IMG_HEIGHT(720)) u_cartoon_96 (
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_tlast(gain_last), .I_tuser(gain_user),
    .I_tdata(gain_data), .I_tvalid(gain_valid),
    .I_edge_data(edge_O_tdata), .O_tdata(cartoon_O_tdata)
);
key_video_mode u_key_video_mode (
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_key(I_key_bin), .I_frame_start(gain_user), .O_mode(video_mode)
);

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        normal_data_d1 <= 96'd0;
        binary_data_d1 <= 96'd0;
        video_mode_d1 <= 3'd0;
        normal_data_d2 <= 96'd0;
        binary_data_d2 <= 96'd0;
        video_mode_d2 <= 3'd0;
    end else begin
        normal_data_d1 <= gain_data;
        binary_data_d1 <= bin_O_tdata;
        video_mode_d1 <= video_mode;
        normal_data_d2 <= normal_data_d1;
        binary_data_d2 <= binary_data_d1;
        video_mode_d2 <= video_mode_d1;
    end
end
grayscale_rgb96 u_grayscale (
    .I_tdata(normal_data_d2),.O_tdata(grayscale_data)
);
    // Display gains favor red and attenuate blue. Segment ungained AWB RGB
    // so display color tuning cannot change the detection thresholds.
    color_reduce_rgb96 u_color_reduce (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_tdata(awb_O_tdata), .I_tvalid(awb_O_tvalid), .I_tuser(awb_O_tuser), .I_tlast(awb_O_tlast),
        .O_valid(reduced_valid), .O_color(reduced_color), .O_x(reduced_x), .O_y(reduced_y)
    );
    color_shape_detect u_color_shape_detect (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_valid(reduced_valid), .I_color(reduced_color), .I_x(reduced_x), .I_y(reduced_y),
        .O_boxes(raw_detected_boxes), .O_count(raw_detected_count), .O_overflow(raw_detected_overflow),
        .O_update(raw_detected_update), .O_busy(),.O_capture_valid(capture_valid),
        .O_capture_done(capture_done),.O_debug(raw_debug)
    );
    detection_result_stabilizer u_detection_stabilizer (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_update(raw_detected_update),
        .I_boxes(raw_detected_boxes),.I_count(raw_detected_count),.I_overflow(raw_detected_overflow),
        .O_boxes(detected_boxes),.O_count(detected_count),.O_overflow(detected_overflow),.O_update(stable_update)
    );
    always @(posedge axi4s_video_aclk or negedge I_rst_n)
        if(!I_rst_n) published_debug<=0;
        else if(stable_update) published_debug<=raw_debug;
    key_remove_shakes u_detection_key (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n), .I_key_in(I_key_detect),
        .O_key_trig_out(detection_key_pressed)
    );
    always @(posedge axi4s_video_aclk or negedge I_rst_n)
        if(!I_rst_n) detection_enabled<=1'b1;
        else if(detection_key_pressed) detection_enabled<=~detection_enabled;
    // Saturation affects the selected display image, before all OSD graphics.
    // Color detection uses ungained AWB RGB.
    saturation_rgb96 u_saturation (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
        .I_tdata(processed_data),.I_tvalid(edge_O_tvalid),.I_tuser(edge_O_tuser),.I_tlast(edge_O_tlast),
        .I_mode(video_mode_d2),.O_tdata(saturation_data),
        .O_tvalid(saturation_valid),.O_tuser(saturation_user),.O_tlast(saturation_last),.O_mode(saturation_mode)
    );
    mode_osd_rgb96 #(.IMG_WIDTH(1280)) u_mode_osd (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_mode(saturation_mode), .I_tdata(saturation_data),
        .I_tvalid(saturation_valid), .I_tuser(saturation_user), .I_tlast(saturation_last),
        .O_tdata(osd_data), .O_tvalid(osd_valid), .O_tuser(osd_user), .O_tlast(osd_last)
    );
    detection_mask_osd_rgb96 u_detection_mask_osd (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_enable(detection_enabled),
        .I_capture_valid(capture_valid),.I_capture_done(capture_done),.I_result_update(stable_update),
        .I_x(reduced_x),.I_y(reduced_y),.I_color(reduced_color),
        .I_tdata(osd_data),.I_tvalid(osd_valid),.I_tuser(osd_user),.I_tlast(osd_last),
        .O_tdata(mask_osd_data),.O_tvalid(mask_osd_valid),.O_tuser(mask_osd_user),.O_tlast(mask_osd_last)
    );
    detection_overlay_rgb96 #(.DIAGNOSTICS(1)) u_detection_overlay (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n), .I_enable(detection_enabled),
        .I_boxes(detected_boxes), .I_count(detected_count), .I_overflow(detected_overflow),
        .I_debug(display_debug),
        .I_tdata(mask_osd_data), .I_tvalid(mask_osd_valid), .I_tuser(mask_osd_user), .I_tlast(mask_osd_last),
        .O_tdata(detection_data), .O_tvalid(detection_valid), .O_tuser(detection_user), .O_tlast(detection_last)
    );
    logo_osd_rgb96 u_logo_osd (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
        .I_tdata(detection_data),.I_tvalid(detection_valid),.I_tuser(detection_user),.I_tlast(detection_last),
        .O_tdata(logo_data),.O_tvalid(logo_valid),.O_tuser(logo_user),.O_tlast(logo_last)
    );
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( logo_user    ),
        .I_96b_valid        ( logo_valid   ),
        .I_96b_data         ( logo_data    ),
	
        .O_128b_frame_start ( display_user_128  	),
        .O_128b_valid       ( display_valid_128 	),
        .O_128b_data        ( display_data_128  	)
    );

	
endmodule
