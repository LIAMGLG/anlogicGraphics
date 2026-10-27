// Frame-constant gray-world AWB. Preserve the original 2 + RAM-delay + 2
// pixel path and the EARLY input SOF used by video_in FIFO reset/latency tags.
module awb #(
    parameter IMG_HEIGHT=1080, IMG_WIDTH=1920,
    parameter integer AUTO_ENABLE=1
)(
    input wire I_clk,I_rst_n,I_tlast,I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    output wire I_tready,O_tlast,O_tuser,
    output wire [95:0] O_tdata,
    output wire O_tvalid,
    input wire O_tready,
    output wire O_stats_valid,
    output wire [7:0] O_luma,
    output wire O_high,
    output reg O_color_change
);
    wire [31:0] sum_r,sum_g,sum_b;
    wire neutral_valid,pre_stats_valid;
    // White-point estimation must use the uncorrected channels.
    image_stats_rgb96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_stats(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
        .I_tvalid(I_tvalid),.I_tdata(I_tdata),.O_valid(pre_stats_valid),
        .O_luma(),.O_high(),.O_r(sum_r),.O_g(sum_g),.O_b(sum_b),
        .O_neutral_valid(neutral_valid));
    // Exposure must meter the RGB actually supplied to NORMAL display and
    // detection, including WB gain/clipping. This is a read-only tap: no new
    // video stage, SOF delay, RAM, clock or ready dependency. Unused neutral
    // sums here, and unused luma sums above, are synthesis-prunable.
    image_stats_rgb96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_ae_stats(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tlast(O_tlast),.I_tuser(I_tuser),
        .I_tvalid(O_tvalid),.I_tdata(O_tdata),.O_valid(O_stats_valid),
        .O_luma(O_luma),.O_high(O_high),.O_r(),.O_g(),.O_b(),.O_neutral_valid());
    wire [47:0] qr,qb;
    wire done;
    // Reuse the two existing divider IPs; one transaction per complete frame.
    divider div_gen_G_R_r1(.clk(I_clk),.rst(!I_rst_n),
        .start(AUTO_ENABLE!=0 && pre_stats_valid && neutral_valid),
        .denominator(sum_r),.numerator({sum_g,16'd0}),.quotient(qr),.done(done),.remainder());
    divider divide_G_B_r1(.clk(I_clk),.rst(!I_rst_n),
        .start(AUTO_ENABLE!=0 && pre_stats_valid && neutral_valid),
        .denominator(sum_b),.numerator({sum_g,16'd0}),.quotient(qb),.done(),.remainder());
    reg [19:0] in_r_r1,in_b_r1,pending_r,pending_b;
    reg pending_valid;
    function [19:0] smooth;
        input [47:0] q;
        input [19:0] old;
        reg [19:0] limited;
        reg signed [20:0] delta;
        begin
            if(q<48'd32768) limited=20'd32768;
            else if(q>48'd131072) limited=20'd131072;
            else limited=q[19:0];
            delta=$signed({1'b0,limited})-$signed({1'b0,old});
            smooth=$signed({1'b0,old})+(delta >>> 3);
        end
    endfunction
    function changed;
        input [19:0] a,b;
        begin changed=(a>b ? a-b:b-a)>20'd1024;end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            in_r_r1<=20'h10000;in_b_r1<=20'h10000;
            pending_r<=20'h10000;pending_b<=20'h10000;pending_valid<=0;O_color_change<=0;
        end else begin
            O_color_change<=0;
            if(I_tuser && pending_valid) begin
                in_r_r1<=pending_r;in_b_r1<=pending_b;pending_valid<=0;
                O_color_change<=changed(pending_r,in_r_r1) || changed(pending_b,in_b_r1);
            end
            if(done && AUTO_ENABLE!=0) begin
                pending_r<=smooth(qr,in_r_r1);pending_b<=smooth(qb,in_b_r1);pending_valid<=1;
            end
        end
    end
    reg [95:0] I_tdata_d0,I_tdata_d1;
    reg I_tvalid_r0,I_tvalid_r1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin I_tdata_d0<=0;I_tdata_d1<=0;I_tvalid_r0<=0;I_tvalid_r1<=0;end
        else begin I_tdata_d0<=I_tdata;I_tdata_d1<=I_tdata_d0;I_tvalid_r0<=I_tvalid;I_tvalid_r1<=I_tvalid_r0;end
    end
    wire [95:0] data_d0;
    wire valid_d0,unused_delayed_user;
    signal_delay #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH),.DATA_WIDTH(96),.DELAY_CYCLE(50)) signal_delay_d(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),.I_valid(I_tvalid_r1),.I_data(I_tdata_d1),
        .O_valid(valid_d0),.O_data(data_d0),.O_tuser(unused_delayed_user));
    reg [95:0] data_d1;
    reg valid_d1,valid_d2;
    reg [27:0] rp[0:3],bp[0:3];
    reg [7:0] gp[0:3];
    integer lane;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            data_d1<=0;valid_d1<=0;valid_d2<=0;
            for(lane=0;lane<4;lane=lane+1) begin rp[lane]<=0;bp[lane]<=0;gp[lane]<=0;end
        end else begin
            data_d1<=data_d0;valid_d1<=valid_d0;valid_d2<=valid_d1;
            if(valid_d1) for(lane=0;lane<4;lane=lane+1) begin
                rp[lane]<=in_r_r1*data_d1[lane*24+16 +:8];
                gp[lane]<=data_d1[lane*24+8 +:8];
                bp[lane]<=in_b_r1*data_d1[lane*24 +:8];
            end
        end
    end
    genvar k;
    generate for(k=0;k<4;k=k+1) begin: pixels
        assign O_tdata[k*24 +:24]=!O_tvalid ? 24'd0 : {
            (|rp[k][27:24]) ? 8'hff:rp[k][23:16],gp[k],
            (|bp[k][27:24]) ? 8'hff:bp[k][23:16]};
    end endgenerate
    assign O_tvalid=valid_d2;
    assign O_tlast=!valid_d1 && valid_d2;
    assign O_tuser=I_tuser;
    assign I_tready=O_tready;
endmodule
