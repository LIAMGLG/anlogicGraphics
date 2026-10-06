`timescale 1ns/1ps
module tb_runtime_thresholds;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,k2=1,k3=1,sof=0,sw1=0;
    wire [7:0] b,default_b;
    wire [10:0] e,default_e;
    key_isp_thresholds #(.BIN_RESET(240),.EDGE_RESET(380)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_key_threshold(k2),.I_key_edge(k3),
        .I_adjust_enable(sw1),.I_frame_start(sof),.O_threshold(b),.O_edge_th(e));
    key_isp_thresholds defaults (
        .I_clk(clk),.I_rst_n(rst_n),.I_key_threshold(k2),.I_key_edge(k3),
        .I_adjust_enable(sw1),.I_frame_start(sof),.O_threshold(default_b),.O_edge_th(default_e));
    reg [7:0] test_threshold=0;
    reg [95:0] data=0;
    wire [95:0] binary_data;
    binary_threshold_96 #(.DYNAMIC_THRESHOLD(1)) bin_dut (
        .I_threshold(test_threshold),.I_tdata(data),.I_tlast(1'b0),.I_tuser(1'b0),.I_tvalid(1'b1),
        .O_tdata(binary_data),.O_tlast(),.O_tuser(),.O_tvalid());
    integer th,lane,luma;
    reg [23:0] pixel;
    reg [95:0] expected;
    task check;
        input [7:0] want_b;input [10:0] want_e;
        begin #1;if(b!==want_b || e!==want_e) $fatal(1,"Threshold mismatch b=%d e=%d",b,e);end
    endtask
    task frame;
        input [7:0] want_b;input [10:0] want_e;
        begin
            @(negedge clk);sof=1;check(want_b,want_e);
            @(negedge clk);sof=0;check(want_b,want_e);
        end
    endtask
    task press;
        input press_b,press_e;input [7:0] old_b;input [10:0] old_e;
        begin
            @(negedge clk);k2=!press_b;k3=!press_e;
            repeat(200030) @(negedge clk);check(old_b,old_e);
            k2=1;k3=1;repeat(10) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;check(240,380);
        #1;if(default_b!==64 || default_e!==60) $fatal(1,"Startup defaults mismatch");
        // Low switch disables both keys without resetting thresholds.
        press(1,1,240,380);frame(240,380);
        #1;if(default_b!==64 || default_e!==60) $fatal(1,"Disabled keys changed defaults");
        @(negedge clk);sw1=1;repeat(5) @(negedge clk);
        press(1,0,240,380);frame(255,380); // saturation and independent k2
        #1;if(default_b!==80 || default_e!==60) $fatal(1,"Default step mismatch");
        press(0,1,255,380);frame(255,400); // independent k3
        press(1,1,255,400);frame(0,0);     // simultaneous wrap
        press(1,1,0,0);frame(16,20);       // step after wrap
        // Disabled presses are consumed, including a held key across enable.
        @(negedge clk);sw1=0;repeat(5) @(negedge clk);
        press(1,1,16,20);frame(16,20);
        @(negedge clk);k2=0;k3=0;
        repeat(200030) @(negedge clk);frame(16,20);
        @(negedge clk);sw1=1;
        repeat(200030) @(negedge clk);frame(16,20);
        k2=1;k3=1;repeat(10) @(negedge clk);
        press(1,1,16,20);frame(32,40);
        // A pulse shorter than debounce interval must not advance either key.
        @(negedge clk);k2=0;k3=0;
        repeat(5) @(negedge clk);k2=1;k3=1;
        repeat(100030) @(negedge clk);frame(32,40);
        for(th=0;th<256;th=th+1) begin
            test_threshold=th;expected=0;
            data={24'hffffff,24'h000000,24'h6480b0,24'hff0000};
            for(lane=0;lane<4;lane=lane+1) begin
                pixel=data[95-lane*24 -:24];
                luma=(pixel[23:16]/4)+(pixel[15:8]/2)+(pixel[7:0]/4);
                expected[95-lane*24 -:24]=(luma>=th) ? 24'hffffff:24'd0;
            end
            #1;if(binary_data!==expected) $fatal(1,"Dynamic binary threshold mismatch th=%d",th);
        end
        @(negedge clk);rst_n=0;check(240,380);
        $display("PASS: runtime thresholds, sw1 enable/disable and held-key enable transition, startup, independent and simultaneous keys, debounce, held keys, frame commit, maxima, wrap and all 256 binary thresholds");
        $finish;
    end
endmodule
