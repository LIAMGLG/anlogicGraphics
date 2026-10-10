// Four RGB888 pixels to gray: Y=floor((R+2G+B)/4), R'=G'=B'=Y.
// Combinational conversion on an already aligned, registered video path.
module grayscale_rgb96 (
    input wire [95:0] I_tdata,
    output wire [95:0] O_tdata
);
    function [23:0] gray_pixel;
        input [23:0] pixel;
        reg [9:0] sum;
        begin
            sum={2'b0,pixel[23:16]}+{1'b0,pixel[15:8],1'b0}+{2'b0,pixel[7:0]};
            gray_pixel={3{sum[9:2]}};
        end
    endfunction
    assign O_tdata={gray_pixel(I_tdata[95:72]),gray_pixel(I_tdata[71:48]),
                   gray_pixel(I_tdata[47:24]),gray_pixel(I_tdata[23:0])};
endmodule
