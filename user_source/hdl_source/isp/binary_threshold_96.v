// Binarize four RGB888 pixels using the luminance approximation
// R/4 + G/2 + B/4. Pixels at or above THRESHOLD become white.
module binary_threshold_96 #(
    parameter [7:0] THRESHOLD = 8'd128,
    parameter integer DYNAMIC_THRESHOLD = 0
)(
    input  wire [7:0]  I_threshold,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [95:0] O_tdata,
    output wire        O_tvalid
);

    wire [7:0] threshold_value = DYNAMIC_THRESHOLD ? I_threshold : THRESHOLD;
    function [23:0] binarize_pixel;
        input [23:0] pixel;
        input [7:0] threshold;
        reg [7:0] luminance;
        begin
            luminance = {2'b0, pixel[23:18]} +
                        {1'b0, pixel[15:9]} +
                        {2'b0, pixel[7:2]};
            binarize_pixel = (luminance >= threshold) ? 24'hffffff : 24'h000000;
        end
    endfunction

    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tvalid = I_tvalid;
    assign O_tdata  = {
        binarize_pixel(I_tdata[95:72],threshold_value),
        binarize_pixel(I_tdata[71:48],threshold_value),
        binarize_pixel(I_tdata[47:24],threshold_value),
        binarize_pixel(I_tdata[23:0],threshold_value)
    };

endmodule
