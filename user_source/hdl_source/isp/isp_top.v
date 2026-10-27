module isp_top #(parameter integer AUTO_AWB=1, AUTO_AE=1, NATURAL_COLOR=1, SHOW_EXPOSURE=1) (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_key_bin		,   // key1: normal / binary / edge / cartoon / gray / motion
    input wire [29:0] I_exposure_status,
    input wire      I_camera_adjust, // synchronized sensor-write event, never a video reset
    output wire O_stats_valid,O_stats_high,
    output wire [7:0] O_stats_luma,
    input wire      I_key_detect,    // k4: toggle detection overlays
    input wire      I_motion_inhibit, // SW1 auto aiming: camera may move
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
    output 			I_tready,
    output wire [255:0] O_target_boxes,
    output wire [3:0] O_target_held,
    output wire O_target_update,O_target_overflow,
    output wire [15:0] O_camera_frame_id,O_target_frame_id
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
  wire awb_color_change;
  reg [2:0] imaging_hold;
  always @(posedge axi4s_video_aclk or negedge I_rst_n)
      if(!I_rst_n) imaging_hold<=0;
      else if(I_camera_adjust || awb_color_change) imaging_hold<=4;
      else if(awb_O_tuser && imaging_hold!=0) imaging_hold<=imaging_hold-1'b1;
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
  wire [3:0] detected_held;
  wire [31:0] display_debug;
  wire [95:0] mask_osd_data;
  wire mask_osd_valid,mask_osd_user,mask_osd_last;
  wire detection_key_pressed;
  reg detection_enabled;
  reg [95:0] normal_data_d1, binary_data_d1, normal_data_d2, binary_data_d2;
  reg [2:0] video_mode_d1, video_mode_d2;
  reg [95:0] motion_rgb_d1,motion_rgb_d2,motion_rgb_d3,motion_rgb_d4;
  wire [143:0] motion_regions;
  wire motion_ready,motion_selected;
  // Conservative suppression for the whole auto-aim interval. Synchronize the
  // switch locally; after release allow 12 video frames for mechanical settling.
  (* async_reg="true" *) reg motion_inhibit1,motion_inhibit2;
  reg [3:0] motion_settle;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n) begin motion_inhibit1<=0;motion_inhibit2<=0;motion_settle<=0;end
      else begin
          motion_inhibit1<=I_motion_inhibit;motion_inhibit2<=motion_inhibit1;
          if(motion_inhibit2) motion_settle<=12;
          else if(edge_O_tuser && motion_settle!=0) motion_settle<=motion_settle-1'b1;
      end
  end
  wire [95:0] motion_data;
  wire motion_valid,motion_user,motion_last;
  reg [2:0] overlay_mode_d1,overlay_mode_d2,overlay_mode_d3;
  wire [95:0] processed_data = (video_mode_d2 == 3'd4) ? grayscale_data :
                               (video_mode_d2 == 3'd3) ? cartoon_O_tdata :
                               (video_mode_d2 == 3'd2) ? edge_O_tdata :
                               (video_mode_d2 == 3'd1) ? binary_data_d2 : normal_data_d2;
  assign awb_O_tready = O_tready;
  // Timestamp the mask actually accepted by CCL, not every incoming frame.
  reg [15:0] camera_frame_id,captured_frame_id,result_frame_id;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n) begin camera_frame_id<=0;captured_frame_id<=0;result_frame_id<=0;end
      else begin
          if(awb_O_tuser) camera_frame_id<=camera_frame_id+1'b1;
          if(capture_valid && reduced_x==0 && reduced_y==0)
              captured_frame_id<=camera_frame_id+(awb_O_tuser ? 16'd1 : 16'd0);
          if(raw_detected_update) result_frame_id<=captured_frame_id;
      end
  end
  assign O_camera_frame_id=camera_frame_id;
  assign O_target_frame_id=result_frame_id;
  assign O_target_boxes=detected_boxes;
  assign O_target_held=detected_held;
  assign O_target_update=stable_update;
  assign O_target_overflow=detected_overflow;
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
    .AUTO_ENABLE(AUTO_AWB),
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .O_stats_valid(O_stats_valid),.O_luma(O_stats_luma),.O_high(O_stats_high),.O_color_change(awb_color_change),
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

color_gain_rgb96 #(.NEUTRAL(NATURAL_COLOR)) u_color_gain (
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
// Match the two-clock gain and two-clock edge alignment, while preserving
// ungained AWB pixels for motion detection. Existing video/control latency stays.
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        motion_rgb_d1<=0;motion_rgb_d2<=0;motion_rgb_d3<=0;motion_rgb_d4<=0;
        overlay_mode_d1<=0;overlay_mode_d2<=0;overlay_mode_d3<=0;
    end else begin
        motion_rgb_d1<=awb_O_tdata;motion_rgb_d2<=motion_rgb_d1;
        motion_rgb_d3<=motion_rgb_d2;motion_rgb_d4<=motion_rgb_d3;
        overlay_mode_d1<=saturation_mode;overlay_mode_d2<=overlay_mode_d1;
        overlay_mode_d3<=overlay_mode_d2;
    end
end
motion_detect_rgb96 u_motion_detect (
    .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
    .I_enable(video_mode_d2==3'd5 && !motion_inhibit2 && motion_settle==0 && imaging_hold==0),
    .I_tdata(motion_rgb_d4),.I_tvalid(edge_O_tvalid),.I_tuser(edge_O_tuser),.I_tlast(edge_O_tlast),
    .O_regions(motion_regions),.O_ready(motion_ready)
);
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
    target_tracker u_target_tracker (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_update(raw_detected_update),
        .I_boxes(raw_detected_boxes),.I_count(raw_detected_count),.I_overflow(raw_detected_overflow),
        .I_frame_start(awb_O_tuser),.I_debug(raw_debug),.O_debug(display_debug),.O_held(detected_held),.O_busy(),
        .O_boxes(detected_boxes),.O_count(detected_count),.O_overflow(detected_overflow),.O_update(stable_update)
    );
    key_remove_shakes u_detection_key (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n), .I_key_in(I_key_detect),
        .O_key_trig_out(detection_key_pressed)
    );
    always @(posedge axi4s_video_aclk or negedge I_rst_n)
        if(!I_rst_n) detection_enabled<=1'b1;
        else if(detection_key_pressed) detection_enabled<=~detection_enabled;
    // Saturation affects the selected display image, before all OSD graphics.
    // Color detection uses ungained AWB RGB.
    saturation_rgb96 #(.BOOST_ENABLE(!NATURAL_COLOR)) u_saturation (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
        .I_tdata(processed_data),.I_tvalid(edge_O_tvalid),.I_tuser(edge_O_tuser),.I_tlast(edge_O_tlast),
        .I_mode(video_mode_d2),.O_tdata(saturation_data),
        .O_tvalid(saturation_valid),.O_tuser(saturation_user),.O_tlast(saturation_last),.O_mode(saturation_mode)
    );
    mode_osd_rgb96 #(.IMG_WIDTH(1280),.SHOW_EXPOSURE(SHOW_EXPOSURE),.AUTO_AE(AUTO_AE)) u_mode_osd (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_exposure_status(I_exposure_status),.I_mode(saturation_mode), .I_tdata(saturation_data),
        .I_tvalid(saturation_valid), .I_tuser(saturation_user), .I_tlast(saturation_last),
        .O_tdata(osd_data), .O_tvalid(osd_valid), .O_tuser(osd_user), .O_tlast(osd_last)
    );
    detection_mask_osd_rgb96 u_detection_mask_osd (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_enable(detection_enabled && saturation_mode!=3'd5),
        .I_capture_valid(capture_valid),.I_capture_done(capture_done),.I_result_update(stable_update),
        .I_x(reduced_x),.I_y(reduced_y),.I_color(reduced_color),
        .I_tdata(osd_data),.I_tvalid(osd_valid),.I_tuser(osd_user),.I_tlast(osd_last),
        .O_tdata(mask_osd_data),.O_tvalid(mask_osd_valid),.O_tuser(mask_osd_user),.O_tlast(mask_osd_last)
    );
    detection_overlay_rgb96 #(.COORDINATES(1)) u_detection_overlay (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n), .I_enable(detection_enabled && overlay_mode_d3!=3'd5),
        .I_boxes(detected_boxes), .I_count(detected_count), .I_overflow(detected_overflow),
        .I_held(detected_held),
        .I_tdata(mask_osd_data), .I_tvalid(mask_osd_valid), .I_tuser(mask_osd_user), .I_tlast(mask_osd_last),
        .O_tdata(detection_data), .O_tvalid(detection_valid), .O_tuser(detection_user), .O_tlast(detection_last)
    );
    motion_overlay_rgb96 u_motion_overlay (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_enable(detection_enabled),
        .I_motion(overlay_mode_d3==3'd5),.I_ready(motion_ready),.I_regions(motion_regions),
        .I_tdata(mask_osd_data),.I_tvalid(mask_osd_valid),.I_tuser(mask_osd_user),.I_tlast(mask_osd_last),
        .O_tdata(motion_data),.O_tvalid(motion_valid),.O_tuser(motion_user),.O_tlast(motion_last),
        .O_motion(motion_selected)
    );
    logo_osd_rgb96 u_logo_osd (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
        .I_tdata(motion_selected ? motion_data : detection_data),
        .I_tvalid(detection_valid),.I_tuser(detection_user),.I_tlast(detection_last),
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
