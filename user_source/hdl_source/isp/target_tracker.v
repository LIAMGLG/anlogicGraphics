// Four fixed track slots. Globally nearest eligible pair is selected repeatedly.
// No pixel storage, multiplier, divider or clock-domain crossing. Input updates
// must be separated by >=256 clocks (the CCL producer easily exceeds this).
// Record layout is identical to color_shape_detect. Held boxes are not counted.
module target_tracker #(
    parameter integer STABLE_UPDATES=3,
    parameter integer MAX_MISSES=2,
    parameter integer MAX_HOLD_FRAMES=12,
    parameter integer MATCH_MARGIN=32
)(
    input wire I_clk,I_rst_n,I_update,I_overflow,I_frame_start,
    input wire [255:0] I_boxes,
    input wire [2:0] I_count,
    input wire [31:0] I_debug,
    output reg [255:0] O_boxes,
    output reg [3:0] O_held,
    output reg [2:0] O_count,
    output reg [31:0] O_debug,
    output reg O_overflow,O_update,
    output wire O_busy
);
    localparam IDLE=0,GEOMETRY=1,SCORE=2,SELECT=3,APPLY=4,
               AGE=5,ALLOCATE=6,PUBLISH=7;
    reg [2:0] state;
    reg [255:0] incoming,next_boxes;
    reg [31:0] incoming_debug,next_debug;
    reg incoming_overflow;
    reg [2:0] incoming_count;
    reg [3:0] used_input,used_slot,next_held,refreshed;
    reg [1:0] i,j,best_i,best_j,slot;
    reg found,eligible;
    reg [13:0] best_distance;
    reg signed [12:0] dx;
    reg signed [11:0] dy;
    reg [12:0] limit_x;
    reg [11:0] limit_y;
    reg [1:0] pending[0:3];
    reg [2:0] repeats[0:3];
    reg [7:0] misses[0:3],frame_age[0:3];
    wire [63:0] current=incoming[i*64 +:64];
    wire [63:0] previous=O_boxes[j*64 +:64];
    wire [63:0] matched=incoming[best_i*64 +:64];
    wire [63:0] old_match=O_boxes[best_j*64 +:64];
    wire [12:0] abs_x=dx<0 ? -dx : dx;
    wire [11:0] abs_y=dy<0 ? -dy : dy;
    wire [13:0] distance={1'b0,abs_x}+{2'b0,abs_y};
    wire [2:0] run_length=pending[best_j]==matched[60:59] ? repeats[best_j]+1'b1 : 3'd1;
    wire [11:0] cw={1'b0,current[37:27]}-{1'b0,current[58:48]}+12'd1;
    wire [11:0] pw={1'b0,previous[37:27]}-{1'b0,previous[58:48]}+12'd1;
    wire [10:0] ch={1'b0,current[26:17]}-{1'b0,current[47:38]}+11'd1;
    wire [10:0] ph={1'b0,previous[26:17]}-{1'b0,previous[47:38]}+11'd1;
    reg [255:0] published_boxes;
    reg [31:0] published_debug;
    reg [3:0] published_held;
    reg [2:0] published_count,expiry_count;
    integer k,n;
    assign O_busy=state!=IDLE;
    // Watchdog uses video SOF, not detection-update count. Never wrap ages.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(n=0;n<4;n=n+1) frame_age[n]<=0;
        end else begin
            for(n=0;n<4;n=n+1) begin
                if(state==PUBLISH && refreshed[n]) frame_age[n]<=0;
                else if(I_frame_start && frame_age[n]<MAX_HOLD_FRAMES)
                    frame_age[n]<=frame_age[n]+1'b1;
            end
        end
    end
    always @(*) begin
        published_boxes=next_boxes;published_debug=next_debug;
        published_held=next_held;published_count=0;expiry_count=0;
        for(k=0;k<4;k=k+1) begin
            if(!refreshed[k] && (frame_age[k]>=MAX_HOLD_FRAMES ||
                (I_frame_start && frame_age[k]>=MAX_HOLD_FRAMES-1))) begin
                published_boxes[k*64 +:64]=0;published_debug[k*8 +:8]=0;
                published_held[k]=0;
            end
            if(published_boxes[k*64+63] && !published_held[k]) published_count=published_count+1'b1;
            if(O_boxes[k*64+63] && !O_held[k] && frame_age[k]<MAX_HOLD_FRAMES-1)
                expiry_count=expiry_count+1'b1;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;incoming<=0;next_boxes<=0;incoming_debug<=0;next_debug<=0;
            incoming_overflow<=0;incoming_count<=0;used_input<=0;used_slot<=0;
            next_held<=0;refreshed<=0;i<=0;j<=0;best_i<=0;best_j<=0;slot<=0;
            found<=0;eligible<=0;best_distance<=14'h3fff;dx<=0;dy<=0;limit_x<=0;limit_y<=0;
            O_boxes<=0;O_debug<=0;O_held<=0;O_count<=0;O_overflow<=0;O_update<=0;
            for(k=0;k<4;k=k+1) begin pending[k]<=0;repeats[k]<=0;misses[k]<=0;end
        end else begin
            O_update<=0;
            case(state)
                IDLE:begin
                    if(I_update) begin
                        incoming<=I_boxes;incoming_debug<=I_debug;incoming_count<=I_count;
                        incoming_overflow<=I_overflow;next_boxes<=O_boxes;next_debug<=O_debug;
                        next_held<=0;used_input<=0;used_slot<=0;refreshed<=0;
                        i<=0;j<=0;slot<=0;found<=0;best_distance<=14'h3fff;
                        state<=I_overflow ? AGE : GEOMETRY;
                    end else if(I_frame_start) begin
                        O_count<=expiry_count;
                        for(k=0;k<4;k=k+1) if(frame_age[k]>=MAX_HOLD_FRAMES-1) begin
                            O_boxes[k*64 +:64]<=0;O_debug[k*8 +:8]<=0;O_held[k]<=0;
                            pending[k]<=0;repeats[k]<=0;misses[k]<=0;
                        end
                    end
                end
                GEOMETRY:begin
                    // Doubled centers avoid fractional coordinates.
                    dx<=$signed({2'b0,current[58:48]})+$signed({2'b0,current[37:27]})-
                        $signed({2'b0,previous[58:48]})-$signed({2'b0,previous[37:27]});
                    dy<=$signed({2'b0,current[47:38]})+$signed({2'b0,current[26:17]})-
                        $signed({2'b0,previous[47:38]})-$signed({2'b0,previous[26:17]});
                    limit_x<={1'b0,cw}+{1'b0,pw}+2*MATCH_MARGIN;
                    limit_y<={1'b0,ch}+{1'b0,ph}+2*MATCH_MARGIN;
                    eligible<=i<incoming_count && current[63] && previous[63] &&
                        !used_input[i] && !used_slot[j] && frame_age[j]<MAX_HOLD_FRAMES &&
                        current[62:61]==previous[62:61] &&
                        {2'b0,cw}<={pw,2'b0} && {2'b0,pw}<={cw,2'b0} &&
                        {2'b0,ch}<={ph,2'b0} && {2'b0,ph}<={ch,2'b0};
                    state<=SCORE;
                end
                SCORE:begin
                    if(eligible && abs_x<=limit_x && abs_y<=limit_y && distance<best_distance) begin
                        found<=1;best_i<=i;best_j<=j;best_distance<=distance;
                    end
                    if(j==3) begin
                        j<=0;
                        if(i==3) state<=SELECT;else begin i<=i+1'b1;state<=GEOMETRY;end
                    end else begin j<=j+1'b1;state<=GEOMETRY;end
                end
                SELECT:begin
                    if(found) state<=APPLY;else begin slot<=0;state<=AGE;end
                end
                APPLY:begin
                    next_boxes[best_j*64 +:64]<=matched;
                    next_debug[best_j*8 +:8]<=incoming_debug[best_i*8 +:8];
                    used_input[best_i]<=1;used_slot[best_j]<=1;refreshed[best_j]<=1;
                    misses[best_j]<=0;pending[best_j]<=matched[60:59];repeats[best_j]<=0;
                    if(matched[60:59]!=old_match[60:59] && run_length<STABLE_UPDATES) begin
                        next_boxes[best_j*64+59 +:2]<=old_match[60:59];repeats[best_j]<=run_length;
                    end
                    i<=0;j<=0;found<=0;best_distance<=14'h3fff;state<=GEOMETRY;
                end
                AGE:begin
                    if(!used_slot[slot] && next_boxes[slot*64+63]) begin
                        repeats[slot]<=0;
                        next_debug[slot*8 +:8]<=0; // no current contour measurement
                        if(frame_age[slot]>=MAX_HOLD_FRAMES || (!incoming_overflow && misses[slot]>=MAX_MISSES)) begin
                            next_boxes[slot*64 +:64]<=0;pending[slot]<=0;misses[slot]<=0;
                        end else begin
                            next_held[slot]<=1;
                            if(!incoming_overflow) misses[slot]<=misses[slot]+1'b1;
                        end
                    end
                    if(slot==3) begin i<=0;j<=0;state<=incoming_overflow ? PUBLISH : ALLOCATE;end
                    else slot<=slot+1'b1;
                end
                ALLOCATE:begin
                    if(i>=incoming_count || !current[63] || used_input[i]) begin
                        if(i==3) state<=PUBLISH;else begin i<=i+1'b1;j<=0;end
                    end else if(!next_boxes[j*64+63]) begin
                        next_boxes[j*64 +:64]<=current;next_debug[j*8 +:8]<=incoming_debug[i*8 +:8];
                        next_held[j]<=0;refreshed[j]<=1;used_input[i]<=1;
                        pending[j]<=current[60:59];repeats[j]<=0;misses[j]<=0;
                        if(i==3) state<=PUBLISH;else begin i<=i+1'b1;j<=0;end
                    end else if(j==3) begin
                        if(i==3) state<=PUBLISH;else begin i<=i+1'b1;j<=0;end
                    end else j<=j+1'b1;
                end
                PUBLISH:begin
                    O_boxes<=published_boxes;O_debug<=published_debug;O_held<=published_held;
                    O_count<=published_count;O_overflow<=incoming_overflow;O_update<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
