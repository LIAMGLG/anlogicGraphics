`timescale 1ns/1ps
module tb_video_latency;
    reg clk=0,src=0,dst=0;
    always #5 clk=~clk;
    always #7 src=~src;
    always #11 dst=~dst;
    reg rst=0;
    reg send=0;reg [64:0] payload=0;
    wire busy,cdc_error,received;wire [64:0] received_data;
    latency_cdc cdc(rst,src,send,payload,busy,cdc_error,dst,received,received_data);
    reg mv=0,ws=0,commit=0,rs=0;reg [64:0] md=0;
    reg [1:0] wp=0,rp=0;reg [24:0] addr=0;
    wire pub,bad,slot_error;wire [64:0] selected;
    latency_slots #(.FRAME_WORDS(4)) slots(clk,rst,mv,md,ws,wp,commit,addr,rs,rp,pub,selected,bad,slot_error);
    reg cs=0,raw=0,isp=0;reg [31:0] cap_us=100;
    wire [31:0] latest;wire [64:0] tag;wire cap_error;
    reg cap_time_valid=1;
    latency_capture capture(clk,rst,cs,raw,isp,cap_us,cap_time_valid,latest,tag,cap_error);
    reg vs=0,hs=0,de=0,omv=0,obad=0;
    reg [31:0] now_us=73450,latest_id=102;reg [64:0] ometa={1'b1,32'd100,32'd10000};
    reg [23:0] rgb=24'h123456;
    wire ovs,ohs,ode;wire [23:0] orgb;wire valid;
    wire [31:0] latency,age,display_id;
    reg [10:0] reason=0;
    latency_osd osd(clk,rst,now_us,latest_id,omv,ometa,obad,reason,vs,hs,de,rgb,ovs,ohs,ode,orgb,valid,latency,age,display_id);
    wire [31:0] time_us;wire tick;
    reg [3:0] number_row=0;
    wire [15:0] four_bits;
    osd_char_lib number_font(.I_char(8'h34),.I_row(number_row),.O_row_bits(four_bits));
    latency_timebase #(.CLOCKS_PER_US(100)) clock_test(clk,rst,time_us,tick);
    function [24:0] base(input integer slot);
        case(slot) 0:base=0;1:base=7000000;2:base=14000000;default:base=21000000;endcase
    endfunction
    task step; begin @(posedge clk);#1;end endtask
    task select_slot(input integer slot,input bit expected_valid,input integer expected_id);
        begin
            @(negedge clk);rp=slot;rs=1;step();
            if(!pub || selected[64]!==expected_valid || (!bad)!==expected_valid)
                $fatal(1,"slot validity mismatch slot=%0d meta=%h",slot,selected);
            if(expected_valid && selected[63:32]!=expected_id) $fatal(1,"slot ID mismatch");
            @(negedge clk);rs=0;step();
        end
    endtask
    task write_slot(input integer slot,input integer id,input bit meta_first);
        begin
            @(negedge clk);md={1'b1,32'(id),32'(id*100)};wp=slot;
            if(meta_first) mv=1;else ws=1;
            step();@(negedge clk);mv=0;ws=0;step();
            @(negedge clk);if(meta_first) ws=1;else mv=1;
            step();@(negedge clk);mv=0;ws=0;step();step();
            for(integer w=0;w<4;w=w+1) begin
                @(negedge clk);commit=1;addr=base(slot)+w*8;step();
                @(negedge clk);commit=0;step();
                if(w==1) select_slot(slot,0,0);
            end
            select_slot(slot,1,id);
        end
    endtask
    reg cdc_done=0,slots_done=0,capture_done=0,osd_done=0;
    initial begin
        #41;rst=1;
        wait(cdc_done&&slots_done&&capture_done&&osd_done);
        $display("PASS: latency CDC, frame association, four-slot rotation, incomplete/repeat/overwrite, OSD/control, timestamp rollover");
        $finish;
    end
    initial begin
        wait(rst);
        for(integer k=0;k<12;k=k+1) begin
            @(negedge src);payload={1'b1,32'(k*1234567),32'h89abcdef^32'(k)};send=1;
            @(negedge src);send=0;
            // The live input may change; the held mailbox must not.
            payload=0;
            wait(received);#1;
            if(received_data!=={1'b1,32'(k*1234567),32'h89abcdef^32'(k)}) $fatal(1,"torn CDC data");
            wait(!busy);@(negedge src);
        end
        if(cdc_error) $fatal(1,"unexpected mailbox error");
        @(negedge src);send=1;@(negedge src);send=0;
        @(negedge src);send=1;@(negedge src);send=0;
        if(!cdc_error) $fatal(1,"mailbox overrun not detected");
        cdc_done=1;
    end
    initial begin
        wait(rst);step();select_slot(0,0,0);
        for(integer k=0;k<8;k=k+1) write_slot(k%4,k+1,k%2);
        select_slot(3,1,8);select_slot(3,1,8);
        @(negedge clk);wp=3;ws=1;step();
        if(!bad) $fatal(1,"read/write collision not invalidated");
        @(negedge clk);ws=0;step();select_slot(3,0,0);
        if(slot_error) $fatal(1,"unexpected slot sequencing fault");
        slots_done=1;
    end
    initial begin
        wait(rst);cap_time_valid=0;
        @(negedge clk);cs=1;step();@(negedge clk);cs=0;cap_time_valid=1;raw=1;step();
        @(negedge clk);raw=0;isp=1;
        if(tag[64]) $fatal(1,"unready timestamp became valid after capture");
        step();@(negedge clk);isp=0;step();
        if(cap_error) $fatal(1,"timestamp warm-up incorrectly became permanent error");
        @(negedge clk);cs=1;step();@(negedge clk);cs=0;raw=1;step();
        @(negedge clk);raw=0;isp=1;
        if(tag!=={1'b1,32'd2,32'd100}) $fatal(1,"capture ID/time association");
        step();@(negedge clk);isp=0;step();
        if(cap_error) $fatal(1,"unexpected capture error");
        @(negedge clk);isp=1;step();
        if(!cap_error || tag[64]) $fatal(1,"duplicate SOF not rejected");
        @(negedge clk);isp=0;capture_done=1;
    end
    task pixel(input bit active);
        bit outside;
        bit cyan_probe;
        begin
            @(negedge clk);de=active;hs=~hs;#1;
            outside=!osd.panel;
            cyan_probe=active && ((osd.x==18 && osd.y==612) || (osd.x==215 && osd.y==668));
            step();
            if(ode!==de || ohs!==hs || ovs!==vs) $fatal(1,"OSD control misalignment");
            if(outside && orgb!==rgb) $fatal(1,"OSD altered outside pixel");
            if(cyan_probe && orgb!==24'h00ffff) $fatal(1,"CAP glyph or decimal point wrong");
        end
    endtask
    reg [11:0] probe_x;
    task check_frame_digits(input [39:0] expected_cap,input [39:0] expected_disp);
        begin
            force osd.x=probe_x;force osd.y=12'd608;
            for(integer d=0;d<10;d=d+1) begin
                probe_x=16+(5+d)*16;#1;
                if(osd.ch!==8'h30+((expected_cap>>((9-d)*4)) & 4'hf)) $fatal(1,"CAP decimal digit mismatch");
            end
            force osd.y=12'd624;
            for(integer d=0;d<10;d=d+1) begin
                probe_x=16+(5+d)*16;#1;
                if(osd.ch!==8'h30+((expected_disp>>((9-d)*4)) & 4'hf)) $fatal(1,"DISP decimal digit mismatch");
            end
            release osd.x;release osd.y;
        end
    endtask
    initial begin
        wait(rst);@(negedge clk);vs=1;step();@(negedge clk);vs=0;step();
        @(negedge clk);omv=1;step();@(negedge clk);omv=0;step();
        pixel(1);
        if(!valid || latency!=63450 || age!=2 || display_id!=100) $fatal(1,"latency measurement mismatch");
        for(integer y=0;y<672;y=y+1) begin
            for(integer x=(y==0 ? 1:0);x<400;x=x+1) pixel(1);
            pixel(0);pixel(0);
        end
        if(osd.latency_bcd!==40'h0000063450 || osd.age_bcd!==40'h0000000002)
            $fatal(1,"decimal conversion wrong");
        if(osd.cap_bcd!==40'h0000000102 || osd.disp_bcd!==40'h0000000100)
            $fatal(1,"CAP/DISP must be decimal rather than hex");
        check_frame_digits(40'h0000000102,40'h0000000100);
        number_row=1;#1;if(four_bits!==16'h300c) $fatal(1,"4 numeric top/width mismatch");
        number_row=12;#1;if(four_bits!==16'h000c) $fatal(1,"4 numeric baseline mismatch");
        if(time_us==0) $fatal(1,"timebase not counting");
        @(negedge clk);vs=1;step();@(negedge clk);vs=0;step();
        ometa={1'b1,32'hfffffffe,32'd10000};latest_id=32'hffffffff;
        @(negedge clk);omv=1;step();@(negedge clk);omv=0;step();pixel(1);
        repeat(128) step();
        if(!valid || osd.cap_bcd!==40'h4294967295 || osd.disp_bcd!==40'h4294967294)
            $fatal(1,"full-range decimal frame IDs wrong");
        check_frame_digits(40'h4294967295,40'h4294967294);pixel(0);
        @(negedge clk);vs=1;step();@(negedge clk);vs=0;step();
        ometa={1'b1,32'd100,32'hfffffff0};now_us=32'h20;latest_id=102;
        @(negedge clk);omv=1;step();@(negedge clk);omv=0;step();pixel(1);
        if(!valid || latency!=48) $fatal(1,"timestamp rollover wrong");
        pixel(0);@(negedge clk);obad=1;reason=11'h200;step();
        if(valid) $fatal(1,"fault did not suppress measurement");
        if(osd.display_reason!==16'h0200) $fatal(1,"WAIT underflow code wrong");
        force osd.x=12'd192;force osd.y=12'd656;#1;
        if(osd.ch!=="2") $fatal(1,"WAIT reason hex character wrong");
        release osd.x;release osd.y;
        osd_done=1;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
