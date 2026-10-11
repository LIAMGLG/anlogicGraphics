// Bundled-data mailbox. Payload stays fixed until the destination acknowledges.
// Caller must not send while busy. A violation is sticky and invalidates metrics.
module latency_cdc #(parameter WIDTH=65)(
    input wire I_rst_n, I_src_clk, I_send,
    input wire [WIDTH-1:0] I_data,
    output wire O_busy,
    output reg O_error,
    input wire I_dst_clk,
    output reg O_valid,
    output reg [WIDTH-1:0] O_data
);
    reg [WIDTH-1:0] held;
    reg req,ack;
    (* async_reg="true" *) reg ack1,ack2,req1,req2;
    reg settle;
    assign O_busy=req!=ack2;
    always @(posedge I_src_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin held<=0;req<=0;ack1<=0;ack2<=0;O_error<=0;end
        else begin
            ack1<=ack;ack2<=ack1;
            if(I_send) begin
                if(O_busy) O_error<=1;
                else begin held<=I_data;req<=~req;end
            end
        end
    end
    always @(posedge I_dst_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin req1<=0;req2<=0;ack<=0;settle<=0;O_valid<=0;O_data<=0;end
        else begin
            req1<=req;req2<=req1;O_valid<=0;
            if(req2!=ack) begin
                if(!settle) settle<=1;
                else begin O_data<=held;O_valid<=1;ack<=req2;settle<=0;end
            end else settle<=0;
        end
    end
endmodule
