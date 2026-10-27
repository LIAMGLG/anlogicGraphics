`timescale 1ns/1ps
// Behavioral vendor divider/RAM; actual AWB, statistics, delay and CDC RTL.
module divider(input clk,rst,start,input [31:0] denominator,input [47:0] numerator,
    output reg [47:0] quotient,output reg done,output [31:0] remainder);
    assign remainder=0;
    always @(posedge clk) begin
        done<=!rst && start;
        if(rst) quotient<=0;
        else if(start) quotient<=numerator/denominator;
    end
endmodule
module blk_mem_gen_awb_delay_signal(input clka,wea,input [10:0] addra,
    input [95:0] dia,input clkb,input [10:0] addrb,output reg [95:0] dob);
    reg [95:0] mem[0:2047];
    always @(posedge clka) if(wea) mem[addra]<=dia;
    always @(posedge clkb) dob<=mem[addrb];
endmodule
module tb_auto_imaging;
    reg clk=0; always #5 clk=~clk;
    reg dst=0; always #7 dst=~dst;
    reg rst=0,user=0,valid=0,last=0;
    wire [95:0] pixels;
    wire pv;
    awb #(.IMG_WIDTH(256),.IMG_HEIGHT(64)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tuser(user),.I_tvalid(valid),.I_tlast(last),
        .I_tdata({4{24'h508064}}),.O_tready(1'b1),.O_tdata(pixels),.O_tvalid(pv));
    wire stats_valid,stats_high,nv;
    wire [7:0] stats_luma;
    wire [31:0] sr,sg,sb;
    image_stats_rgb96 #(.IMG_WIDTH(256),.IMG_HEIGHT(64)) meter(
        .I_clk(clk),.I_rst_n(rst),.I_tuser(user),.I_tvalid(valid),.I_tlast(last),.I_tdata({4{24'h508064}}),
        .O_valid(stats_valid),.O_luma(stats_luma),.O_high(stats_high),
        .O_r(sr),.O_g(sg),.O_b(sb),.O_neutral_valid(nv));
    wire busy,cdc_error,received;
    wire [8:0] payload;
    latency_cdc #(.WIDTH(9)) bridge(.I_rst_n(rst),.I_src_clk(clk),.I_send(stats_valid),
        .I_data({stats_high,stats_luma}),.O_busy(busy),.O_error(cdc_error),
        .I_dst_clk(dst),.O_valid(received),.O_data(payload));
    integer count=0,transfers=0,out_count=0;
    reg [19:0] previous_r=65536,previous_b=65536;
    reg previous_user=0;
    always @(posedge clk) begin
        previous_user<=user;
        #1;
        if(rst) begin
            if((dut.in_r_r1!=previous_r || dut.in_b_r1!=previous_b) && !previous_user)
                $fatal(1,"AWB gain changed inside frame");
            previous_r=dut.in_r_r1;previous_b=dut.in_b_r1;
            if(stats_valid) begin
                count=count+1;
                if(stats_luma!==8'd109 || stats_high || !nv || sr!=20480 || sg!=32768 || sb!=25600)
                    $fatal(1,"ROI statistics wrong: %d %d %d %d",stats_luma,sr,sg,sb);
            end
            if(pv) begin
                out_count=out_count+1;
                if(^pixels===1'bx) $fatal(1,"unknown corrected pixel");
            end
        end
    end
    always @(posedge dst) begin
        #1;
        if(received) begin
            transfers=transfers+1;
            if(payload!==9'd109) $fatal(1,"CDC payload torn");
        end
    end
    task frame(input integer rows);
        integer y,x;
        begin
            @(negedge clk);user=1;
            @(negedge clk);user=0;
            for(y=0;y<rows;y=y+1) begin
                for(x=0;x<64;x=x+1) begin
                    @(negedge clk);valid=1;last=x==63;
                end
                @(negedge clk);valid=0;last=0;
                repeat(70) @(negedge clk);
            end
            repeat(100) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        frame(10);
        if(count!=0) $fatal(1,"incomplete frame accepted");
        frame(64);frame(64);frame(64);
        if(count!=3 || transfers!=3 || cdc_error) $fatal(1,"stats/mailbox count");
        if(dut.in_r_r1<=65536 || dut.in_b_r1<=65536) $fatal(1,"AWB correction direction");
        if(out_count<3*4096) $fatal(1,"AWB pixels dropped");
        $display("PASS: complete-frame ROI, AWB frame-boundary correction and asynchronous metering");
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
module tb_natural_color;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0;
    reg [95:0] data=0;
    wire [95:0] gained,saturated;
    wire gv,gu,gl,sv,su,sl;
    color_gain_rgb96 #(.NEUTRAL(1)) gain_stage(.I_clk(clk),.I_rst_n(rst),
        .I_tdata(data),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
        .O_tdata(gained),.O_tvalid(gv),.O_tuser(gu),.O_tlast(gl));
    saturation_rgb96 #(.BOOST_ENABLE(0)) saturation_stage(.I_clk(clk),.I_rst_n(rst),
        .I_tdata(data),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_mode(3'd3),
        .O_tdata(saturated),.O_tvalid(sv),.O_tuser(su),.O_tlast(sl));
    reg [95:0] d1=0,d2=0;
    reg [2:0] c1=0,c2=0;
    always @(posedge clk) begin
        if(!rst) begin d1<=0;d2<=0;c1<=0;c2<=0;end
        else begin d1<=data;d2<=d1;c1<={valid,user,last};c2<=c1;end
        #1;
        if(rst && (gained!==d2 || saturated!==d2 || {gv,gu,gl}!==c2 || {sv,su,sl}!==c2))
            $fatal(1,"natural colors or two-cycle controls changed");
    end
    integer i;
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(i=0;i<256;i=i+1) begin
            @(negedge clk);data={$random,$random,$random};valid=i%7!=0;user=i==0;last=i%32==31;
        end
        repeat(4) @(negedge clk);
        $display("PASS: natural color preserves RGB and stream alignment");$finish;
    end
endmodule
module tb_ae_control;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,stats=0,high=0,err=0,done=1;
    reg [7:0] luma=135;
    reg [3:0] buttons=15;
    wire req,fault,applied;
    wire [15:0] ae,ag;
    wire [7:0] target;
    ae_set #(.CLK_HZ(1000),.WARMUP_FRAMES(2),.SETTLE_FRAMES(1)) dut(
        .I_clk(clk),.I_rst(rst),.I_btn(buttons),.I_cam_cfg_done(1'b1),.I_ae_cfg_done(done),
        .I_iic_error(err),.I_stats_valid(stats),.I_high(high),.I_luma(luma),
        .O_ae_req(req),.O_ae(ae),.O_ag(ag),.O_target(target),.O_fault(fault),.O_applied(applied));
    wire [29:0] status;
    ae_display_status display_numbers(.I_clk(clk),.I_rst_n(!rst),.I_applied(applied),
        .I_fault(fault),.I_ae(ae[10:0]),.I_ag(ag[7:0]),.O_status(status));
    integer writes=0,busy=0;
    always @(posedge clk) begin
        if(req) begin writes=writes+1;done<=0;busy<=5;end
        else if(busy>0) begin busy<=busy-1;if(busy==1) done<=1;end
    end
    task sample(input [7:0] value);
        begin
            @(negedge clk);luma=value;stats=1;
            @(negedge clk);stats=0;
            repeat(300) @(negedge clk);
        end
    endtask
    integer old_ae,old_writes;
    initial begin
        repeat(4) @(negedge clk);rst=0;
        sample(135);sample(135);
        if(writes!=0) $fatal(1,"warmup missing");
        sample(135);
        if(writes!=1 || ae!=1991 || ag!=16 || !status[28] || status[27:0]!=28'h1660100)
            $fatal(1,"initial exposure/status %h",status);
        sample(135);
        old_ae=ae;sample(220);
        if(ae>=old_ae || ag!=16) $fatal(1,"bright image exposure must decrease");
        sample(135);old_ae=ae;sample(40);
        if(ae<=old_ae) $fatal(1,"dark image exposure must increase");
        @(negedge clk);buttons=4'b1011;repeat(15) @(negedge clk);buttons=15;
        repeat(15) @(negedge clk);
        if(target!=130) $fatal(1,"k2 target minus");
        old_writes=writes;err=1;sample(40);err=0;sample(40);
        if(!fault || writes!=old_writes) $fatal(1,"I2C fault must stop sensor requests");
        $display("PASS: AE warmup, settling, exposure direction, target key, fault and displayed setpoints");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
