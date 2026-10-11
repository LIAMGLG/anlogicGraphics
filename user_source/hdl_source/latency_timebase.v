// I_sys_clk is 50 MHz (20 ns in timing.sdc). One tick = one microsecond.
module latency_timebase #(parameter CLOCKS_PER_US=50)(
    input wire I_clk,I_rst_n, output reg [31:0] O_us,output reg O_tick
);
    reg [7:0] divider;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin O_us<=0;divider<=0;O_tick<=0;end
        else begin
            O_tick<=0;
            if(divider==CLOCKS_PER_US-1) begin divider<=0;O_us<=O_us+32'd1;O_tick<=1;end
            else divider<=divider+1'b1;
        end
    end
endmodule
