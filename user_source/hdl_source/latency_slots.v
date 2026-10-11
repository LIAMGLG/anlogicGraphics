// All inputs are in the DDR domain. Metadata mailbox and actual slot-start
// may arrive in either order. Count final memory-controller write commands,
// not merely words queued by video_in, before marking a slot complete.
module latency_slots #(parameter FRAME_WORDS=172800)(
    input wire I_clk,I_rst_n,
    input wire I_meta_valid,input wire [64:0] I_meta,
    input wire I_write_start,input wire [1:0] I_write_slot,
    input wire I_commit,input wire [24:0] I_commit_addr,
    input wire I_read_start,input wire [1:0] I_read_slot,
    output reg O_publish,output reg [64:0] O_read_meta,
    output reg O_read_bad,output reg O_error
);
    reg [64:0] meta[0:3];
    reg [3:0] ready;
    localparam WORD_COUNT_WIDTH=$clog2(FRAME_WORDS+1);
    reg [WORD_COUNT_WIDTH-1:0] words[0:3];
    reg [64:0] waiting_meta;
    reg meta_pending,slot_pending;
    reg [1:0] waiting_slot,read_slot;
    reg read_active;
    integer i;
    wire [1:0] commit_slot=I_commit_addr>=25'd21000000 ? 2'd3 :
                            I_commit_addr>=25'd14000000 ? 2'd2 :
                            I_commit_addr>=25'd7000000 ? 2'd1 : 2'd0;
    wire [24:0] base=commit_slot==3 ? 25'd21000000 :
                     commit_slot==2 ? 25'd14000000 :
                     commit_slot==1 ? 25'd7000000 : 25'd0;
    wire commit_in_frame=I_commit_addr>=base && I_commit_addr<base+FRAME_WORDS*8;
    // The end address proves the controller has reached the last word. The
    // ordered word count also rejects incomplete or duplicated transfers.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ready<=0;meta_pending<=0;slot_pending<=0;waiting_meta<=0;waiting_slot<=0;
            O_publish<=0;O_read_meta<=0;O_read_bad<=1;O_error<=0;read_slot<=0;read_active<=0;
            for(i=0;i<4;i=i+1) begin meta[i]<=0;words[i]<=0;end
        end else begin
            O_publish<=0;
            if(I_write_start) begin
                ready[I_write_slot]<=0;meta[I_write_slot]<=0;words[I_write_slot]<=0;
                waiting_slot<=I_write_slot;slot_pending<=1;
                if(slot_pending) O_error<=1;
                if(read_active && read_slot==I_write_slot) O_read_bad<=1;
            end
            if(I_meta_valid) begin
                waiting_meta<=I_meta;meta_pending<=1;
                if(meta_pending) O_error<=1;
            end
            if(meta_pending && slot_pending) begin
                meta[waiting_slot]<=waiting_meta;meta_pending<=0;slot_pending<=0;
            end
            if(I_commit && commit_in_frame) begin
                if(I_commit_addr==base+words[commit_slot]*8 && words[commit_slot]<FRAME_WORDS) begin
                    words[commit_slot]<=words[commit_slot]+1'b1;
                    if(words[commit_slot]==FRAME_WORDS-1)
                        ready[commit_slot]<=1;
                end else begin ready[commit_slot]<=0;O_error<=1;end
            end
            if(I_read_start) begin
                read_slot<=I_read_slot;read_active<=1;O_publish<=1;
                O_read_meta<={ready[I_read_slot] && meta[I_read_slot][64] && !O_error &&
                              !(I_write_start && I_write_slot==I_read_slot),meta[I_read_slot][63:0]};
                O_read_bad<=!(ready[I_read_slot] && meta[I_read_slot][64] && !O_error) ||
                             (I_write_start && I_write_slot==I_read_slot);
            end
        end
    end
endmodule
