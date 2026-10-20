`timescale 1ns/1ps
module tb_pd_rate;
    reg clk=0,rst=0,update=0,valid=1;
    always #5 clk=~clk;
    reg [1:0] slot=0;
    reg [10:0] x=640;
    reg [9:0] y=360;
    reg [15:0] frame_id=0,sample=0;
    wire done,ov,busy;
    wire signed [8:0] pan,tilt;
    wire [3:0] life;
    gimbal_pd_rate #(.TILT_REVERSE(1)) dut(.I_clk(clk),.I_rst_n(rst),.I_update(update),.I_valid(valid),
        .I_slot(slot),.I_x(x),.I_y(y),.I_frame(frame_id),.I_sample(sample),
        .O_update(done),.O_valid(ov),.O_pan(pan),.O_tilt(tilt),.O_life(life),.O_busy(busy));
    bit hist=0,ax=0,ay=0;
    integer px=0,py=0,ps=0,pid=0;
    integer tests=0,maximum_cycles=0;
    function automatic integer output_rate(input integer e,p,input bit run,reverse);
        integer v;
        begin
            v=0;
            if(run && ((e>0 && p>0)||(e<0 && p<0))) v=p>250 ? 250 : p< -250 ? -250 : p;
            return reverse ? -v : v;
        end
    endfunction
    task automatic observe(input integer nx,ny,ns,nf,nslot,input bit good=1);
        integer age,gap,ex,ey,predx,predy,wpan,wtilt,wlife,cycles;
        bit accept,same,wx,wy,wvalid;
        begin
            age=(nf-ns)&65535;gap=(ns-ps)&65535;
            accept=good && age<8 && (!hist || (gap>0 && gap<32768));
            same=hist && pid==nslot;
            wlife=accept ? (8-age)*5/6 : 0;
            wvalid=accept && wlife!=0;
            wpan=0;wtilt=0;
            if(accept) begin
                ex=640-nx;ey=360-ny;predx=ex;predy=ey;
                if(same && gap<=32) begin
                    predx=ex+(ex-px)*(age+2)/gap;
                    predy=ey+(ey-py)*(age+2)/gap;
                end
                wx=ex>36 || ex< -36 || (same && ax && (ex>24 || ex< -24));
                wy=ey>30 || ey< -30 || (same && ay && (ey>20 || ey< -20));
                if(wvalid) begin wpan=output_rate(ex,predx,wx,0);wtilt=output_rate(ey,predy,wy,1);end
                hist=1;ax=wx;ay=wy;px=ex;py=ey;ps=ns&65535;pid=nslot;
            end else if(!good) begin hist=0;ax=0;ay=0;end
            @(negedge clk);x=nx;y=ny;sample=ns;frame_id=nf;slot=nslot;valid=good;update=1;
            @(negedge clk);update=0;cycles=0;
            while(!done && cycles<128) begin @(negedge clk);cycles++;end
            if(cycles>=128 || ov!==wvalid || $signed(pan)!=wpan || $signed(tilt)!=wtilt || life!=wlife)
                $fatal(1,"PD mismatch test=%0d sample=%0d age=%0d gap=%0d got=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",tests,ns,age,gap,ov,$signed(pan),$signed(tilt),life,wvalid,wpan,wtilt,wlife);
            if(cycles>maximum_cycles) maximum_cycles=cycles;
            tests++;
            @(negedge clk);
        end
    endtask
    integer i,ss,age,r,seed=32'h13579;
    initial begin
        #17;rst=1;
        observe(440,200,1,4,0);if(pan!=200) $fatal(1,"initial P response");
        observe(540,280,4,7,0);if(pan!=0 || tilt!=0) $fatal(1,"must brake before reaching center");
        observe(540,280,7,10,0);if(pan!=100) $fatal(1,"stationary visual error restores P");
        observe(540,280,7,10,0); // duplicate does not refresh a valid rate
        observe(540,280,6,10,0); // out of order
        observe(540,280,8,16,0); // too old
        observe(540,280,9,10,0,0); // held/lost clears velocity
        observe(540,280,10,12,1); // new slot must not inherit velocity
        observe(640,360,11,12,1);
        observe(610,335,12,13,1);if(pan!=0 || tilt!=0) $fatal(1,"restart hysteresis");
        observe(400,200,65534,65535,2,0);
        observe(400,200,65534,65535,2);
        observe(420,220,1,3,2); // modular wrap interval=3
        ss=1;
        for(i=0;i<800;i++) begin
            r=$random(seed)&32'h7fffffff;ss=(ss+1+r%35)&65535;
            r=$random(seed)&32'h7fffffff;age=r%10;
            observe(($random(seed)&32'h7fffffff)%1280,($random(seed)&32'h7fffffff)%720,ss,(ss+age)&65535,(i/43)%4,i%47!=0);
        end
        $display("PASS: %0d PD reference cases, normalized intervals, frame age, pre-center braking, chronology, wrap, slot reset, limits; max cycles=%0d",tests,maximum_cycles);
        $finish;
    end
    initial begin #2000000;$fatal(1,"PD test timeout");end
endmodule