module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_key_bin		,   // key1 (active low): cycles normal / binary / edge / cartoon
    input wire      I_adjust_enable, // sw1 high enables k2/k3
    input wire      I_key_threshold, // k2: raise binary threshold
    input wire      I_key_edge,      // k3: raise Sobel threshold
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
  wire [1:0] saturation_mode;

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  wire         bin_O_tlast;
  wire         bin_O_tuser;
  wire [ 95:0] bin_O_tdata;
  wire         bin_O_tvalid;

  wire [7:0] binary_threshold;
  wire [10:0] edge_threshold;
  wire [1:0] video_mode;
  wire [95:0] edge_O_tdata;
  wire [95:0] cartoon_O_tdata;
  wire edge_O_tlast, edge_O_tuser, edge_O_tvalid;
  wire [95:0] osd_data;
  wire osd_last, osd_user, osd_valid;
  wire [95:0] detection_data;
  wire detection_last, detection_user, detection_valid;
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
  reg [1:0] video_mode_d1, video_mode_d2;
  wire [95:0] processed_data = (video_mode_d2 == 2'd3) ? cartoon_O_tdata :
                               (video_mode_d2 == 2'd2) ? edge_O_tdata :
                               (video_mode_d2 == 2'd1) ? binary_data_d2 : normal_data_d2;
  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = detection_last;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
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
    .THRESHOLD(8'd64), .DYNAMIC_THRESHOLD(1)
) u_binary_threshold_96 (
    .I_threshold(binary_threshold),
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
    .IMG_WIDTH(1280), .IMG_HEIGHT(720), .EDGE_TH(11'd60), .DYNAMIC_THRESHOLD(1)
) u_edge_detect_96 (
    .I_edge_th(edge_threshold),
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
key_isp_thresholds #(.BIN_RESET(8'd64), .EDGE_RESET(11'd60)) u_key_isp_thresholds (
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_adjust_enable(I_adjust_enable),
    .I_key_threshold(I_key_threshold), .I_key_edge(I_key_edge),
    .I_frame_start(gain_user), .O_threshold(binary_threshold), .O_edge_th(edge_threshold)
);
key_video_mode u_key_video_mode (
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_key(I_key_bin), .I_frame_start(gain_user), .O_mode(video_mode)
);

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        normal_data_d1 <= 96'd0;
        binary_data_d1 <= 96'd0;
        video_mode_d1 <= 2'd0;
        normal_data_d2 <= 96'd0;
        binary_data_d2 <= 96'd0;
        video_mode_d2 <= 2'd0;
    end else begin
        normal_data_d1 <= gain_data;
        binary_data_d1 <= bin_O_tdata;
        video_mode_d1 <= video_mode;
        normal_data_d2 <= normal_data_d1;
        binary_data_d2 <= binary_data_d1;
        video_mode_d2 <= video_mode_d1;
    end
end
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
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( detection_user    ),
        .I_96b_valid        ( detection_valid   ),
        .I_96b_data         ( detection_data    ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule

// Four-pixel RGB888 gamma stage.  The 16-segment curve approximates
// y = 255 * (x / 255)^0.7.  It lifts shadows and mid-tones while preserving
// black and white and adds one registered pipeline cycle.
module axis_gamma_rgb96 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid
);

    function [7:0] gamma07;
        input [7:0] value;
        reg [7:0] base;
        reg [7:0] delta;
        reg [11:0] interpolation;
        begin
            case (value[7:4])
                4'h0: begin base = 8'd0;   delta = 8'd37; end
                4'h1: begin base = 8'd37;  delta = 8'd23; end
                4'h2: begin base = 8'd60;  delta = 8'd19; end
                4'h3: begin base = 8'd79;  delta = 8'd18; end
                4'h4: begin base = 8'd97;  delta = 8'd16; end
                4'h5: begin base = 8'd113; delta = 8'd16; end
                4'h6: begin base = 8'd129; delta = 8'd14; end
                4'h7: begin base = 8'd143; delta = 8'd14; end
                4'h8: begin base = 8'd157; delta = 8'd14; end
                4'h9: begin base = 8'd171; delta = 8'd13; end
                4'ha: begin base = 8'd184; delta = 8'd13; end
                4'hb: begin base = 8'd197; delta = 8'd12; end
                4'hc: begin base = 8'd209; delta = 8'd12; end
                4'hd: begin base = 8'd221; delta = 8'd12; end
                4'he: begin base = 8'd233; delta = 8'd11; end
                default: begin base = 8'd244; delta = 8'd11; end
            endcase

            interpolation = delta * value[3:0] + 8;
            if (value == 8'hff)
                gamma07 = 8'hff;
            else
                gamma07 = base + (interpolation >> 4);
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            if (I_tvalid) begin
                O_tdata <= {
                    gamma07(I_tdata[95:88]), gamma07(I_tdata[87:80]), gamma07(I_tdata[79:72]),
                    gamma07(I_tdata[71:64]), gamma07(I_tdata[63:56]), gamma07(I_tdata[55:48]),
                    gamma07(I_tdata[47:40]), gamma07(I_tdata[39:32]), gamma07(I_tdata[31:24]),
                    gamma07(I_tdata[23:16]), gamma07(I_tdata[15:8]),  gamma07(I_tdata[7:0])
                };
            end else begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule


// Centre crop for the ISP's four-pixel-wide RGB888 stream.  Frame start is
// intentionally forwarded at the original frame boundary so video_in can
// reset its asynchronous FIFO before the first selected row arrives.
module axis_crop_rgb96 #(
    parameter integer IN_WIDTH   = 1792,
    parameter integer IN_HEIGHT  = 1080,
    parameter integer OUT_WIDTH  = 1600,
    parameter integer OUT_HEIGHT = 900,
    parameter integer X_START    = 96,
    parameter integer Y_START    = 90
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [95:0] O_tdata,
    output wire        O_tvalid
);

    localparam integer X_START_BEAT = X_START / 4;
    localparam integer OUT_BEATS    = OUT_WIDTH / 4;
    localparam integer X_END_BEAT   = X_START_BEAT + OUT_BEATS;

    reg [9:0]  S_hcnt;
    reg [10:0] S_vcnt;

    wire [9:0]  S_current_h = I_tuser ? 10'd0 : S_hcnt;
    wire [10:0] S_current_v = I_tuser ? 11'd0 : S_vcnt;
    wire S_inside = (S_current_h >= X_START_BEAT) &&
                    (S_current_h < X_END_BEAT) &&
                    (S_current_v >= Y_START) &&
                    (S_current_v < (Y_START + OUT_HEIGHT));

    assign O_tdata  = I_tdata;
    assign O_tvalid = I_tvalid && S_inside;
    assign O_tlast  = O_tvalid && (S_current_h == (X_END_BEAT - 1));
    assign O_tuser  = I_tuser;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_hcnt <= 10'd0;
            S_vcnt <= 11'd0;
        end
        else if(I_tuser) begin
            S_hcnt <= (I_tvalid && !I_tlast) ? 10'd1 : 10'd0;
            S_vcnt <= (I_tvalid && I_tlast) ? 11'd1 : 11'd0;
        end
        else if(I_tvalid) begin
            if(I_tlast) begin
                S_hcnt <= 10'd0;
                S_vcnt <= (S_vcnt == IN_HEIGHT - 1) ? 11'd0 : S_vcnt + 1'b1;
            end
            else begin
                S_hcnt <= S_hcnt + 1'b1;
            end
        end
    end

endmodule
