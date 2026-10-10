// Fixed post-AWB gains for four RGB888 pixels, with unsigned saturation.
// Floor division by 128; data/valid/SOF/last all have two-cycle latency.
module color_gain_rgb96 (
    input wire I_clk,I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    reg [15:0] red_product[0:3];
    reg [14:0] green_product[0:3],blue_product[0:3];
    reg valid_d,user_d,last_d;
    integer lane;
    function [15:0] red;
        input [7:0] v;
        reg [15:0] n;
        begin n={8'd0,v};red=((n<<7)+(n<<4))+((n<<1)+n);end
    endfunction
    function [14:0] green;
        input [7:0] v;
        reg [15:0] n;
        begin n={8'd0,v};green=(n<<7)-((n<<2)+(n<<1));end
    endfunction
    function [14:0] blue;
        input [7:0] v;
        reg [15:0] n;
        begin n={8'd0,v};blue=(n<<7)-((n<<4)+((n<<1)+n));end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(lane=0;lane<4;lane=lane+1) begin
                red_product[lane]<=0;green_product[lane]<=0;blue_product[lane]<=0;
            end
            valid_d<=0;user_d<=0;last_d<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            for(lane=0;lane<4;lane=lane+1) begin
                red_product[lane]<=red(I_tdata[95-lane*24 -:8]);
                green_product[lane]<=green(I_tdata[87-lane*24 -:8]);
                blue_product[lane]<=blue(I_tdata[79-lane*24 -:8]);
                O_tdata[95-lane*24 -:24]<={
                    red_product[lane][15] ? 8'hff : red_product[lane][14:7],
                    green_product[lane][14:7],blue_product[lane][14:7]};
            end
            valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tlast;
            O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;
        end
    end
endmodule
