`timescale 1ns/1ps
module tb_edge_modes;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg last = 0, user = 0, valid = 0;
    reg [95:0] data = 0;
    reg [10:0] edge_threshold=80;
    wire out_last, out_user, out_valid;
    wire [95:0] out_data;
    edge_detect_96 #(.IMG_WIDTH(16), .IMG_HEIGHT(6), .EDGE_TH(80), .DYNAMIC_THRESHOLD(1)) edge_dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_edge_th(edge_threshold), .I_tlast(last), .I_tuser(user),
        .I_tdata(data), .I_tvalid(valid), .I_tready(), .O_tready(1'b1),
        .O_tlast(out_last), .O_tuser(out_user), .O_tdata(out_data), .O_tvalid(out_valid)
    );
    reg key = 1, frame_start = 0;
    wire [2:0] mode;
    key_video_mode mode_dut (.I_clk(clk), .I_rst_n(rst_n), .I_key(key),
        .I_frame_start(frame_start), .O_mode(mode));
    integer gray [0:5][0:7];
    integer frame, y, x, p, lane, level, gx, gy, magnitude;
    reg [95:0] expected;

    task check_mode;
        input [2:0] want;
        begin
            #1;
            if (mode !== want) $fatal(1, "Mode mismatch: got %d want %d", mode, want);
        end
    endtask

    task press_key;
        input [2:0] old_mode;
        input [2:0] new_mode;
        begin
            @(negedge clk); key = 0;
            repeat (100020) @(negedge clk);
            check_mode(old_mode); // request cannot change the current frame
            repeat (100020) @(negedge clk);
            check_mode(old_mode); // long hold must not cycle twice
            key = 1;
            repeat (10) @(negedge clk);
            frame_start = 1;
            check_mode(new_mode); // new mode on the FIRST beat
            @(negedge clk); frame_start = 0;
            check_mode(new_mode);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        check_mode(0);
        // Constant, vertical step, horizontal step, and texture frames.
        // Alternate SOF with first valid data and SOF during blanking.
        for (frame = 0; frame < 4; frame = frame + 1) begin
            for (y = 0; y < 6; y = y + 1)
                for (x = 0; x < 8; x = x + 1) begin
                    case(frame)
                        0: gray[y][x] = 128;
                        1: gray[y][x] = x < 4 ? 0 : 252;
                        2: gray[y][x] = y < 3 ? 0 : 252;
                        3: gray[y][x] = ((y * 19 + x * 37) % 64) * 4;
                    endcase
                end
            if (frame % 2) begin
                @(negedge clk); user = 1; valid = 0;
                @(negedge clk); user = 0;
            end
            for (y = 0; y < 6; y = y + 1) begin
                for (x = 0; x < 4; x = x + 1) begin
                    @(negedge clk);
                    valid = 1; user = (frame % 2 == 0 && x == 0 && y == 0);
                    last = (x == 3);
                    edge_threshold = (frame == 0) ? 11'd0 : ((x % 2) ? 11'd80 : 11'd2047);
                    expected = 0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        level = gray[y][2*x + lane/2];
                        data[95 - lane*24 -: 24] = {level[7:0],level[7:0],level[7:0]};
                    end
                    if (y >= 2 && x > 0) begin
                        for (p = 0; p < 2; p = p + 1) begin
                            lane = 2*x + p;
                            gx = -gray[y-2][lane-2] + gray[y-2][lane]
                                 -2*gray[y-1][lane-2] + 2*gray[y-1][lane]
                                 -gray[y][lane-2] + gray[y][lane];
                            gy = gray[y-2][lane-2] + 2*gray[y-2][lane-1] + gray[y-2][lane]
                                 -gray[y][lane-2] - 2*gray[y][lane-1] - gray[y][lane];
                            magnitude = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
                            if (magnitude >= edge_threshold) expected[95 - p*48 -: 48] = 48'hffffffffffff;
                        end
                    end
                    @(posedge clk); #1;
                    // Output arrives two registered clocks after the input.
                    @(negedge clk); valid = 0; user = 0; last = 0;
                    @(posedge clk); #1;
                    if (out_data !== expected || out_valid !== 1'b1 || out_last !== (x == 3) ||
                        out_user !== (frame % 2 == 0 && x == 0 && y == 0))
                        $fatal(1, "Edge mismatch frame=%d row=%d group=%d got=%h expected=%h", frame,y,x,out_data,expected);
                    // Bubble in the middle of every row: line state must hold.
                    @(negedge clk); valid = 0; user = 0; last = 0;
                    @(posedge clk); #1;
                    if (out_valid !== 0 || out_data !== 0) $fatal(1, "Invalid beat mismatch");
                end
            end
        end
        // Mid-frame reset followed by SOF must rebuild line memories safely.
        @(negedge clk); rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        check_mode(0);
        @(negedge clk); valid = 1; user = 1; data = {4{24'hffffff}};
        @(posedge clk); #1;
        @(negedge clk); valid = 0; user = 0;
        @(posedge clk); #1;
        if (out_data !== 0 || edge_dut.x_grp !== 1 || edge_dut.y_pos !== 0)
            $fatal(1, "Reset/SOF mismatch");
        @(negedge clk); valid = 0; user = 0;
        press_key(0,1);
        press_key(1,2);
        press_key(2,3);
        press_key(3,4);
        press_key(4,5);
        press_key(5,0);
        $display("PASS: Sobel reference, borders, bubbles, SOF, reset, key debounce and six-mode frame switching");
        $finish;
    end
endmodule
