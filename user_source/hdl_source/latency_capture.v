// The real-time ISP must emit its SOF before the next RAW input SOF.
// Reject missing/duplicate/overlapping frame events instead of guessing an ID.
module latency_capture(
    input wire I_clk,I_rst_n,
    input wire I_csi_start,I_raw_start,I_isp_start,
    input wire [31:0] I_us,
    input wire I_time_valid,
    output reg [31:0] O_latest_id,
    output wire [64:0] O_meta,
    output reg O_error
);
    reg [31:0] capture_us;
    reg csi_seen,raw_used,pending,capture_time_valid;
    reg [63:0] tag;
    reg tag_valid;
    wire raw_ok=(csi_seen || I_csi_start) && (!raw_used || I_csi_start);
    wire [63:0] raw_tag={I_csi_start ? O_latest_id+32'd1 : O_latest_id,
                         I_csi_start ? I_us : capture_us};
    wire raw_time_valid=I_csi_start ? I_time_valid : capture_time_valid;
    assign O_meta={ !O_error && (pending ? tag_valid : (I_raw_start && raw_ok && raw_time_valid)),
                   pending ? tag : raw_tag};
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_latest_id<=0;capture_us<=0;csi_seen<=0;raw_used<=0;
            pending<=0;tag<=0;tag_valid<=0;O_error<=0;capture_time_valid<=0;
        end else begin
            if(I_csi_start) begin
                O_latest_id<=O_latest_id+1'b1;
                capture_us<=I_us;capture_time_valid<=I_time_valid;csi_seen<=1;raw_used<=0;
            end
            if(I_isp_start) begin
                pending<=0;
                if(!pending && !I_raw_start) O_error<=1;
            end
            if(I_raw_start) begin
                raw_used<=1;
                if(!raw_ok || (pending && !I_isp_start)) O_error<=1;
                tag<=raw_tag;tag_valid<=raw_ok && raw_time_valid;
                pending<=!(I_isp_start && !pending);
            end
        end
    end
endmodule
