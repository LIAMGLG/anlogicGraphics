// Debounced runtime thresholds, committed only at the next frame start.
module key_isp_thresholds #(
    parameter [7:0] BIN_RESET = 8'd64,
    parameter [10:0] EDGE_RESET = 11'd60,
    parameter [7:0] BIN_STEP = 8'd16,
    parameter [10:0] EDGE_STEP = 11'd20,
    parameter [10:0] EDGE_MAX = 11'd400
)(
    input wire I_clk, I_rst_n,
    input wire I_key_threshold, I_key_edge,
    input wire I_adjust_enable,
    input wire I_frame_start,
    output wire [7:0] O_threshold,
    output wire [10:0] O_edge_th
);
    wire bin_press, edge_press;
    // Synchronize the physical switch into the ISP pixel clock domain.
    // Debouncers always run; gate event pulses to avoid fake presses
    // when the switch changes while a key is already held down.
    (* ASYNC_REG = "TRUE" *) reg enable_meta, enable_sync;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin enable_meta <= 1'b0; enable_sync <= 1'b0; end
        else begin enable_meta <= I_adjust_enable; enable_sync <= enable_meta; end
    end
    reg [7:0] bin_request, bin_frame;
    reg [10:0] edge_request, edge_frame;
    wire [8:0] bin_next = {1'b0,bin_request} + {1'b0,BIN_STEP};
    wire [11:0] edge_next = {1'b0,edge_request} + {1'b0,EDGE_STEP};
    key_remove_shakes u_bin_key (
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_key_in(I_key_threshold),.O_key_trig_out(bin_press));
    key_remove_shakes u_edge_key (
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_key_in(I_key_edge),.O_key_trig_out(edge_press));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin bin_request<=BIN_RESET;edge_request<=EDGE_RESET; end
        else begin
            if(enable_sync && bin_press) begin
                if(bin_request==8'd255) bin_request<=0;
                else bin_request<=bin_next[8] ? 8'd255 : bin_next[7:0];
            end
            if(enable_sync && edge_press) begin
                if(edge_request>=EDGE_MAX) edge_request<=0;
                else edge_request<=(edge_next>EDGE_MAX) ? EDGE_MAX : edge_next[10:0];
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin bin_frame<=BIN_RESET;edge_frame<=EDGE_RESET; end
        else if(I_frame_start) begin bin_frame<=bin_request;edge_frame<=edge_request; end
    end
    assign O_threshold=I_frame_start ? bin_request : bin_frame;
    assign O_edge_th=I_frame_start ? edge_request : edge_frame;
endmodule
