// 8x8 mean grayscale frame difference. No video backpressure or new clock domain.
// A complete first frame primes RAM; incomplete frames invalidate the reference.
module motion_detect_rgb96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer THRESHOLD=16, REGION_THRESHOLD=8
)(
    input wire I_clk,I_rst_n,I_enable,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [143:0] O_regions,
    output reg O_ready
);
    localparam W=IMG_WIDTH/8, H=IMG_HEIGHT/8;
    localparam LAST_REGION=(H/10-1)*16+(W/10-1);
    reg [8:0] x;
    reg [10:0] y;
    wire [8:0] cx=I_tuser ? 9'd0 : x;
    wire [10:0] cy=I_tuser ? 11'd0 : y;
    reg enabled;
    wire active=I_tuser ? I_enable : enabled;
    function [7:0] gray;
        input [23:0] rgb;
        reg [9:0] sum;
        begin sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]}; gray=sum[9:2]; end
    endfunction
    wire [9:0] four={2'b0,gray(I_tdata[95:72])}+{2'b0,gray(I_tdata[71:48])}+
                     {2'b0,gray(I_tdata[47:24])}+{2'b0,gray(I_tdata[23:0])};
    reg [9:0] half;
    reg [13:0] sums[0:W-1];
    reg [13:0] sum_q;
    reg [10:0] eight;
    reg [7:0] sx;
    reg [10:0] sy;
    reg sv;
    wire [13:0] total=(sy[2:0]==0 ? 14'd0 : sum_q)+{3'd0,eight};
    wire sample=sv && sy[2:0]==7;
    wire first=sample && sx==0 && sy==7;
    wire final_sample=sample && sx==W-1 && sy==IMG_HEIGHT-1;
    reg [7:0] previous[0:W*H-1];
    reg [7:0] prev_q,current_q;
    reg [13:0] address,addr_q;
    reg pending,last_q,compare_q;
    reg reference_valid;
    reg [7:0] sample_x;
    reg [3:0] region_col,region_row,sub_col,sub_row;
    reg [6:0] counts[0:15];
    reg [6:0] count_q;
    reg [7:0] region_q;
    reg region_end_q;
    reg [13:0] received;
    reg [143:0] working,history;
    reg [1:0] hold_count[0:143];
    wire [7:0] difference=current_q>=prev_q ? current_q-prev_q : prev_q-current_q;
    wire hit=compare_q && difference>THRESHOLD;
    wire [6:0] next_count=count_q>=REGION_THRESHOLD ? count_q : count_q+hit;
    wire [143:0] final_map=working | ((region_end_q && next_count>=REGION_THRESHOLD) ?
                                      (144'b1 << LAST_REGION) : 144'd0);
    integer i;
    // Synchronous memories, no reset on data arrays. Read and delayed write
    // use distinct cycles for each address (samples are at least two clocks apart).
    always @(posedge I_clk) begin
        if(I_rst_n && active && I_tvalid && cx[0]) sum_q<=sums[cx>>1];
        if(I_rst_n && sv) sums[sx]<=total;
        if(I_rst_n && sample) prev_q<=previous[first ? 14'd0 : address];
        if(I_rst_n && pending) previous[addr_q]<=current_q;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;enabled<=0;half<=0;sv<=0;sx<=0;sy<=0;eight<=0;
            address<=0;addr_q<=0;current_q<=0;pending<=0;last_q<=0;compare_q<=0;
            reference_valid<=0;received<=0;sample_x<=0;
            region_col<=0;region_row<=0;sub_col<=0;sub_row<=0;
            count_q<=0;region_q<=0;region_end_q<=0;
            working<=0;history<=0;O_regions<=0;O_ready<=0;
            for(i=0;i<16;i=i+1) counts[i]<=0;
            for(i=0;i<144;i=i+1) hold_count[i]<=0;
        end else begin
            if(I_tuser) begin enabled<=I_enable;x<=0;y<=0; end
            sv<=active && I_tvalid && cx[0];
            if(active && I_tvalid) begin
                if(!cx[0]) half<=four;
                else begin eight<={1'b0,half}+{1'b0,four};sx<=cx>>1;sy<=cy; end
                if(I_tlast || cx==IMG_WIDTH/4-1) begin x<=0;y<=cy+1'b1; end
                else begin x<=cx+1'b1;y<=cy; end
            end
            pending<=sample;
            if(sample) begin
                current_q<=total[13:6];addr_q<=first ? 14'd0 : address;
                address<=first ? 14'd1 : address+1'b1;
                last_q<=final_sample;
                compare_q<=reference_valid && (!first || received==W*H);
                if(first) begin
                    if(received!=W*H) reference_valid<=0;
                    received<=1;working<=0;sample_x<=1;
                    region_col<=0;region_row<=0;sub_col<=1;sub_row<=0;
                    count_q<=0;region_q<=0;region_end_q<=0;
                end else begin
                    received<=received+1'b1;
                    count_q<=(sub_row==0 && sub_col==0) ? 7'd0 : counts[region_col];
                    region_q<={region_row,region_col};
                    region_end_q<=sub_row==9 && sub_col==9;
                    if(sample_x==W-1) begin
                        sample_x<=0;region_col<=0;sub_col<=0;
                        if(sub_row==9) begin sub_row<=0;region_row<=region_row+1'b1; end
                        else sub_row<=sub_row+1'b1;
                    end else begin
                        sample_x<=sample_x+1'b1;
                        if(sub_col==9) begin sub_col<=0;region_col<=region_col+1'b1; end
                        else sub_col<=sub_col+1'b1;
                    end
                end
            end
            if(pending) begin
                counts[region_q[3:0]]<=next_count;
                if(region_end_q) working[region_q]<=next_count>=REGION_THRESHOLD;
                if(last_q) begin
                    reference_valid<=1;O_ready<=1;
                    history<=final_map;
                    for(i=0;i<144;i=i+1) begin
                        if(final_map[i] && history[i]) begin O_regions[i]<=1;hold_count[i]<=3; end
                        else if(hold_count[i]!=0) begin O_regions[i]<=1;hold_count[i]<=hold_count[i]-1'b1; end
                        else O_regions[i]<=0;
                    end
                end
            end
            if(!active) begin
                sv<=0;pending<=0;reference_valid<=0;received<=0;
                O_regions<=0;history<=0;working<=0;O_ready<=0;
                for(i=0;i<144;i=i+1) hold_count[i]<=0;
            end
        end
    end
endmodule
