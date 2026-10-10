// key1 cycles normal -> binary -> edge -> cartoon -> gray -> normal.
// Commit at frame start and expose the new mode on the first frame beat.
module key_video_mode #(
    parameter [2:0] RESET_MODE = 3'd0
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_key,
    input wire I_frame_start,
    output wire [2:0] O_mode
);
    wire key_pressed;
    reg [2:0] requested_mode;
    reg [2:0] frame_mode;

    key_remove_shakes u_key_remove_shakes (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_key_in(I_key),
        .O_key_trig_out(key_pressed)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            requested_mode <= RESET_MODE;
        else if (key_pressed)
            requested_mode <= (requested_mode >= 3'd4) ? 3'd0 : requested_mode + 1'b1;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            frame_mode <= RESET_MODE;
        else if (I_frame_start)
            frame_mode <= requested_mode;
    end

    assign O_mode = I_frame_start ? requested_mode : frame_mode;
endmodule
