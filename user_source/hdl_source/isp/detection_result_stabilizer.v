// Associate detections by color and nearest center, then require three
// consecutive contrary classifications before changing an established class.
// Coordinates/count always describe the latest detection; disappeared targets
// are removed immediately. UNKNOWN cannot indefinitely preserve an old class.
module detection_result_stabilizer #(
    parameter integer STABLE_UPDATES=3
)(
    input wire I_clk,I_rst_n,I_update,I_overflow,
    input wire [255:0] I_boxes,
    input wire [2:0] I_count,
    output reg [255:0] O_boxes,
    output reg [2:0] O_count,
    output reg O_overflow,O_update
);
    reg [1:0] pending[0:3];
    reg [2:0] repeats[0:3];
    // I_update pulses are separated by complete CCL runs (>40 cycles).
    reg [255:0] incoming,voted;
    reg [2:0] incoming_count;
    reg incoming_overflow;
    reg [2:0] state;
    reg [1:0] i,j,match;
    wire [63:0] current=incoming[i*64 +:64];
    wire [63:0] previous=O_boxes[j*64 +:64];
    reg [3:0] used;
    reg found,eligible;
    reg [12:0] best_distance;
    reg signed [12:0] dx;
    reg signed [11:0] dy;
    reg [12:0] limit_x;
    reg [11:0] limit_y;
    wire [12:0] abs_x=dx<0 ? -dx : dx;
    wire [11:0] abs_y=dy<0 ? -dy : dy;
    wire [12:0] distance=abs_x+abs_y;
    wire [1:0] old_shape=O_boxes[match*64+59 +:2];
    wire [2:0] run_length=pending[match]==current[60:59] ? repeats[match]+1'b1 : 3'd1;
    reg [1:0] pending_next[0:3];
    reg [2:0] repeats_next[0:3];
    integer k;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_boxes<=0;O_count<=0;O_overflow<=0;O_update<=0;
            incoming<=0;voted<=0;incoming_count<=0;incoming_overflow<=0;
            state<=0;i<=0;j<=0;match<=0;used<=0;found<=0;eligible<=0;best_distance<=8191;
            dx<=0;dy<=0;limit_x<=0;limit_y<=0;
            for(k=0;k<4;k=k+1) begin pending[k]<=0;repeats[k]<=0;pending_next[k]<=0;repeats_next[k]<=0;end
        end else begin
            O_update<=0;
            case(state)
                0:if(I_update) begin
                    incoming<=I_boxes;voted<=I_boxes;incoming_count<=I_count;incoming_overflow<=I_overflow;
                    i<=0;j<=0;found<=0;used<=0;best_distance<=8191;
                    for(k=0;k<4;k=k+1) begin pending_next[k]<=0;repeats_next[k]<=0;end
                    state<=I_overflow || I_count==0 ? 4 : 1;
                end
                1:begin
                    dx<=$signed({2'b0,current[58:48]})+$signed({2'b0,current[37:27]})-
                        $signed({2'b0,previous[58:48]})-$signed({2'b0,previous[37:27]});
                    dy<=$signed({2'b0,current[47:38]})+$signed({2'b0,current[26:17]})-
                        $signed({2'b0,previous[47:38]})-$signed({2'b0,previous[26:17]});
                    limit_x<={2'b0,current[37:27]}-{2'b0,current[58:48]}+
                        {2'b0,previous[37:27]}-{2'b0,previous[58:48]}+2;
                    limit_y<={2'b0,current[26:17]}-{2'b0,current[47:38]}+
                        {2'b0,previous[26:17]}-{2'b0,previous[47:38]}+2;
                    eligible<=current[63] && previous[63] && !used[j] && current[62:61]==previous[62:61];
                    state<=2;
                end
                2:begin
                    if(eligible && abs_x<limit_x && abs_y<limit_y && distance<best_distance) begin
                        found<=1;match<=j;best_distance<=distance;
                    end
                    if(j==3) state<=3;else begin j<=j+1'b1;state<=1;end
                end
                3:begin
                    pending_next[i]<=current[60:59];repeats_next[i]<=0;
                    if(found) begin
                        used[match]<=1;
                        if(current[60:59]!=old_shape) begin
                            if(run_length<STABLE_UPDATES) begin
                                voted[i*64+59 +:2]<=old_shape;repeats_next[i]<=run_length;
                            end
                        end
                    end
                    if(i==3 || i==incoming_count-1'b1) state<=4;
                    else begin i<=i+1'b1;j<=0;found<=0;best_distance<=8191;state<=1;end
                end
                4:begin
                    O_boxes<=incoming_overflow ? 256'd0 : voted;
                    O_count<=incoming_overflow ? 3'd0 : incoming_count;O_overflow<=incoming_overflow;O_update<=1;
                    for(k=0;k<4;k=k+1) begin pending[k]<=pending_next[k];repeats[k]<=repeats_next[k];end
                    state<=0;
                end
                default:state<=0;
            endcase
        end
    end
endmodule
