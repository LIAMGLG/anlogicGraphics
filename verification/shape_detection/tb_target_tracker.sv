`timescale 1ns/1ps
module tb_target_tracker;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,update=0,overflow=0,sof=0;
    reg [255:0] boxes=0;
    reg [31:0] debug_in=0;
    reg [2:0] count=0;
    wire [255:0] result;
    wire [31:0] debug_out;
    wire [3:0] held;
    wire [2:0] result_count;
    wire done,busy,ov;
    integer cycles,max_cycles=0;
    target_tracker #(.MAX_HOLD_FRAMES(6)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_update(update),.I_overflow(overflow),.I_frame_start(sof),
        .I_boxes(boxes),.I_count(count),.I_debug(debug_in),.O_boxes(result),.O_count(result_count),
        .O_debug(debug_out),.O_held(held),.O_overflow(ov),.O_update(done),.O_busy(busy));
    function automatic [63:0] record(input integer x,input integer color,input integer shape);
        reg [63:0] r;
        begin
            r=0;r[63]=1;r[62:61]=color;r[60:59]=shape;
            r[58:48]=x;r[37:27]=x+40;r[47:38]=300;r[26:17]=340;r[16:0]=100;
            record=r;
        end
    endfunction
    task reset;
        begin @(negedge clk);rst=0;update=0;sof=0;repeat(3) @(negedge clk);rst=1;end
    endtask
    task submit(input reg [255:0] value,input integer n,input bit o,input reg [31:0] dbg);
        reg [255:0] prior;
        begin
            @(negedge clk);prior=result;boxes=value;count=n;overflow=o;debug_in=dbg;update=1;
            @(negedge clk);update=0;boxes=0;debug_in=0;cycles=0;
            while(!done && cycles<256) begin
                @(posedge clk);#1;cycles=cycles+1;
                if(!done && result!==prior) $fatal(1,"Non-atomic tracker publication");
            end
            if(!done || busy || ov!==o) $fatal(1,"Tracker completion/overflow contract");
            if(cycles>max_cycles) max_cycles=cycles;
            repeat(2) @(negedge clk);
        end
    endtask
    task check(input reg [255:0] expected,input integer n,input reg [3:0] h,input reg [31:0] dbg);
        begin
            if(result!==expected || result_count!==n || held!==h || debug_out!==dbg)
                $fatal(1,"Tracker got boxes=%h N=%d held=%h debug=%h expected boxes=%h N=%d held=%h debug=%h",
                    result,result_count,held,debug_out,expected,n,h,dbg);
        end
    endtask
    task frame;
        begin @(negedge clk);sof=1;@(negedge clk);sof=0;repeat(2) @(negedge clk);end
    endtask
    initial begin
        reset();
        submit({128'd0,record(600,2,2),record(100,1,1)},2,0,32'h00008240);
        check({128'd0,record(600,2,2),record(100,1,1)},2,0,32'h00008240);
        // Ranking changes; boxes and contour diagnostics follow persistent slots.
        submit({128'd0,record(110,1,1),record(590,2,2)},2,0,32'h00004183);
        check({128'd0,record(590,2,2),record(110,1,1)},2,0,32'h00008341);
        // Confirm contrary shape in three matched updates, including UNKNOWN.
        submit({128'd0,record(585,2,2),record(115,1,3)},2,0,32'h00008030);
        check({128'd0,record(585,2,2),record(115,1,1)},2,0,32'h00008030);
        submit({128'd0,record(580,2,2),record(120,1,3)},2,0,32'h00008030);
        submit({128'd0,record(575,2,2),record(125,1,3)},2,0,32'h00008030);
        check({128'd0,record(575,2,2),record(125,1,3)},2,0,32'h00008030);
        // Two missed completed detections retain ID; busy/skipped video is not a miss.
        submit(record(570,2,2),1,0,32'h80);
        check({128'd0,record(570,2,2),record(125,1,3)},1,1,32'h8000);
        frame();frame();
        submit(record(565,2,2),1,0,32'h80);
        submit({128'd0,record(130,1,3),record(560,2,2)},2,0,32'h00003080);
        check({128'd0,record(560,2,2),record(130,1,3)},2,0,32'h00008030);
        // Third miss clears only the missing slot, leaving a real hole.
        submit(record(555,2,2),1,0,32'h80);
        submit(record(550,2,2),1,0,32'h80);
        submit(record(545,2,2),1,0,32'h80);
        check({128'd0,record(545,2,2),64'd0},1,0,32'h8000);
        submit({128'd0,record(540,2,2),record(900,1,1)},2,0,32'h00008040);
        check({128'd0,record(540,2,2),record(900,1,1)},2,0,32'h00008040);
        // Overflow is an invalid measurement, not a normal miss or new target.
        submit(0,0,1,0);submit(0,0,1,0);submit(0,0,1,0);
        check({128'd0,record(540,2,2),record(900,1,1)},0,3,0);
        submit({128'd0,record(535,2,2),record(905,1,1)},2,0,32'h00008040);
        check({128'd0,record(535,2,2),record(905,1,1)},2,0,32'h00008040);
        // Watchdog expiry without a single detection update.
        repeat(5) frame();
        if(!result[63] || !result[127]) $fatal(1,"Watchdog expired early");
        frame();check(0,0,0,0);
        // Globally nearest pair wins even if incoming rank favours another pair.
        reset();submit({128'd0,record(160,1,2),record(100,1,1)},2,0,32'h8040);
        submit({128'd0,record(105,1,1),record(150,1,2)},2,0,32'h4181);
        check({128'd0,record(150,1,2),record(105,1,1)},2,0,32'h8141);
        // Far same-color target becomes a separate track rather than teleporting ID.
        submit(record(1000,1,1),1,0,32'h40);
        check({64'd0,record(1000,1,1),record(150,1,2),record(105,1,1)},1,3,32'h00400000);
        reset();
        submit({record(1000,2,3),record(700,1,2),record(400,2,1),record(100,1,1)},4,0,32'h30804040);
        submit({record(110,1,1),record(410,2,1),record(710,1,2),record(1010,2,3)},4,0,32'h41418131);
        check({record(1010,2,3),record(710,1,2),record(410,2,1),record(110,1,1)},4,0,32'h31814141);
        // Watchdog ages during matching too; newly matched slots reset at publish.
        @(negedge clk);boxes=result;count=4;debug_in=debug_out;update=1;
        @(negedge clk);update=0;
        repeat(6) frame();
        while(!done) begin @(posedge clk);#1;end
        if(result_count!=4 || held!=0) $fatal(1,"Watchdog/matching collision");
        // All slots occupied: a distant new target waits rather than stealing ID.
        submit(record(1200,1,1),1,0,32'h40);
        if(result_count!=0 || held!=15 || result[58:48]!=110)
            $fatal(1,"Full track table must preserve held identities");
        reset();submit(record(100,1,1),1,0,32'h40);
        // Inclusive 41-pixel widths produce a 73-pixel center-distance gate.
        submit(record(173,1,1),1,0,32'h41);check(record(173,1,1),1,0,32'h41);
        submit(record(100,1,1),1,0,32'h42);check(record(100,1,1),1,0,32'h42);
        submit(record(174,1,1),1,0,32'h43);
        check({128'd0,record(174,1,1),record(100,1,1)},1,1,32'h4300);
        reset();submit(record(100,1,1),1,0,32'h40);
        submit(record(100,1,0),1,0,32'h71);
        submit(record(100,1,0),1,0,32'h71);
        check(record(100,1,1),1,0,32'h71);
        submit(record(100,1,0),1,0,32'h71);check(record(100,1,0),1,0,32'h71);
        // Color mismatch at the same position must not inherit an old identity.
        submit(record(100,2,2),1,0,32'h80);
        check({128'd0,record(100,2,2),record(100,1,0)},1,1,32'h8000);
        reset();check(0,0,0,0);
        $display("PASS: tracker fixed IDs, global matching, four slots, diagnostics, stable shapes, holes, misses/recovery, overflow, SOF watchdog, atomic publish; max cycles=%0d",max_cycles);
        $finish;
    end
    initial begin #200000;$fatal(1,"Tracker timeout");end
endmodule
