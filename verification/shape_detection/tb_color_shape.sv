`timescale 1ns/1ps
module tb_color_shape;
    localparam W=64,H=48,N=W*H;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,valid=0;
    reg [1:0] color=0;
    reg [8:0] x=0;
    reg [7:0] y=0;
    wire [255:0] boxes;
    wire [2:0] count;
    wire overflow,update,busy;
    color_shape_detect #(.WIDTH(W),.HEIGHT(H)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_valid(valid),.I_color(color),.I_x(x),.I_y(y),
        .O_boxes(boxes),.O_count(count),.O_overflow(overflow),.O_update(update),.O_busy(busy),
        .O_capture_valid(),.O_capture_done(),.O_debug());
    integer image[0:N-1],seen[0:N-1],queue[0:N-1];
    reg [63:0] expected[0:3],record;
    integer scene,i,j,xx,yy,a,loX,hiX,loY,hiY,qhead,qtail,p,nx,ny,n,c,sh,w,h,ec,waits;
    reg [31:0] noise_rng;
    task rect(input integer x0,y0,x1,y1,cc);
        for(integer ry=y0;ry<=y1;ry=ry+1)
            for(integer rx=x0;rx<=x1;rx=rx+1) image[ry*W+rx]=cc;
    endtask
    task reference_bfs;
        begin
            for(i=0;i<N;i=i+1) seen[i]=0;
            for(i=0;i<4;i=i+1) expected[i]=0;
            ec=0;
            for(i=0;i<N;i=i+1) if(image[i]!=0 && !seen[i]) begin
                c=image[i]; qhead=0; qtail=1; queue[0]=i; seen[i]=1;
                a=0; loX=W; hiX=0; loY=H; hiY=0;
                while(qhead<qtail) begin
                    p=queue[qhead]; qhead=qhead+1; xx=p%W; yy=p/W; a=a+1;
                    if(xx<loX) loX=xx; if(xx>hiX) hiX=xx;
                    if(yy<loY) loY=yy; if(yy>hiY) hiY=yy;
                    for(j=0;j<4;j=j+1) begin
                        nx=xx; ny=yy;
                        case(j) 0:nx=xx-1; 1:nx=xx+1; 2:ny=yy-1; 3:ny=yy+1; endcase
                        if(nx>=0 && nx<W && ny>=0 && ny<H) begin
                            n=ny*W+nx;
                            if(!seen[n] && image[n]==c) begin
                                seen[n]=1; queue[qtail]=n; qtail=qtail+1;
                            end
                        end
                    end
                end
                w=hiX-loX+1; h=hiY-loY+1;
                if(a>=25 && w>=5 && h>=5) begin
                    sh=0;
                    record=0; record[63]=1; record[62:61]=c; record[60:59]=sh;
                    record[58:48]=loX*4; record[47:38]=loY*4;
                    record[37:27]=hiX*4+3; record[26:17]=hiY*4+3; record[16:0]=a;
                    if(ec<4) ec=ec+1;
                    for(j=0;j<4;j=j+1) if(record[16:0]>expected[j][16:0]) begin
                        for(n=3;n>j;n=n-1) expected[n]=expected[n-1];
                        expected[j]=record; break;
                    end
                end
            end
        end
    endtask
    task send_frame(input bit gaps);
        begin
            for(integer pos=0;pos<N;pos=pos+1) begin
                @(negedge clk); valid=1; x=pos%W; y=pos/W; color=image[pos];
                if(gaps && pos%37==0) begin @(negedge clk); valid=0; end
            end
            @(negedge clk); valid=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=1;
        for(scene=0;scene<28;scene=scene+1) begin
            for(i=0;i<N;i=i+1) image[i]=0;
            case(scene)
                1: begin
                    rect(2,3,13,12,1); rect(30,4,39,11,2);
                    for(yy=0;yy<H;yy=yy+1) for(xx=0;xx<W;xx=xx+1)
                        if((xx-44)*(xx-44)+(yy-32)*(yy-32)<=64) image[yy*W+xx]=3;
                    image[60]=1;
                end
                2: begin
                    rect(2,4,9,11,1); rect(45,4,52,11,1);
                    rect(22,4,24,14,1); rect(34,4,36,14,1); rect(22,14,36,16,1);
                end
                3: begin rect(0,0,8,7,3); rect(55,39,63,47,2); end
                4: for(i=0;i<N;i=i+1) image[i]=((i/W+i%W)%2==0) ? 1 : 0;
                5: for(j=0;j<6;j=j+1) rect(2+(j%3)*20,2+(j/3)*22,7+j+(j%3)*20,7+j+(j/3)*22,j%3+1);
                6: begin rect(0,25,10,40,1); rect(11,25,20,40,2); end
                7: begin
                    rect(20,10,32,22,3); rect(21,11,31,21,0);
                    // Diagonally touching blocks remain distinct with four-connectivity.
                    rect(2,2,7,7,2); rect(8,8,13,13,2);
                end
                8:begin
                    for(yy=0;yy<H;yy=yy+1) for(xx=0;xx<W;xx=xx+1) begin
                        if((xx+yy-30)>=-12 && (xx+yy-30)<=12 &&
                           (xx-yy)>=-6 && (xx-yy)<=6) image[yy*W+xx]=1;
                        if(yy>=6 && yy<=30 && (xx-44)*24<=14*(yy-6) &&
                           (xx-44)*24>=-14*(yy-6)) image[yy*W+xx]=2;
                    end
                end
                9:begin
                    for(yy=0;yy<H;yy=yy+1) for(xx=0;xx<W;xx=xx+1)
                        if((xx-30)*(xx-30)+(yy-24)*(yy-24)<=256) image[yy*W+xx]=3;
                    rect(28,22,31,25,0);
                end
                10:begin
                    // 144 isolated components preceding the target used to
                    // exhaust 31 labels and erase every box in the frame.
                    for(yy=0;yy<24;yy=yy+2) for(xx=1;xx<48;xx=xx+4)
                        image[yy*W+xx]=(xx+yy)%3+1;
                    rect(15,30,35,42,1);
                end
                11:begin
                    // Small merging U components leave parent aliases; after
                    // retirement both the root and aliases must be reusable.
                    for(yy=0;yy<24;yy=yy+4) for(xx=1;xx<55;xx=xx+6) begin
                        rect(xx,yy,xx,yy+2,2);rect(xx+2,yy,xx+2,yy+2,2);
                        rect(xx,yy+2,xx+2,yy+2,2);
                    end
                    rect(12,31,36,43,3);
                end
                12:begin
                    // Active components must survive gaps in individual columns
                    // and retain accumulated area/seed across row reclamation.
                    rect(28,2,42,44,1);
                    for(yy=0;yy<38;yy=yy+2) for(xx=1;xx<23;xx=xx+4)
                        image[yy*W+xx]=3;
                end
                25,26,27:begin
                    // One large component repeatedly acquires two new labels
                    // and merges them into its root. Total allocations >31,
                    // but only three slots need be live in any row. Reclaiming
                    // aliases must preserve cached references, area and seed.
                    rect(30,2,40,44,scene-24);
                    for(yy=2;yy<=44;yy=yy+1) begin
                        if(yy%2==0) begin image[yy*W+26]=scene-24;image[yy*W+28]=scene-24;end
                        else rect(26,yy,40,yy,scene-24);
                    end
                end
                default:if(scene>=13 && scene<25) begin
                    // Deterministic speckles include accidental attachments to
                    // the target. BFS checks resulting geometry rather than
                    // assuming that noise never changes the bounding box.
                    noise_rng=32'h734b51e9+scene;
                    for(i=0;i<N;i=i+1) begin
                        noise_rng=noise_rng^(noise_rng<<13);
                        noise_rng=noise_rng^(noise_rng>>17);
                        noise_rng=noise_rng^(noise_rng<<5);
                        if(noise_rng[7:0]<13) image[i]=noise_rng[9:8]%3+1;
                    end
                    rect(22,12,42,35,scene%3+1);
                end
            endcase
            if(scene!=4) reference_bfs();
            send_frame(scene%2);
            if(scene==2) begin
                // A complete incoming frame while busy must not corrupt mask RAM.
                for(i=0;i<N;i=i+1) image[i]=2;
                send_frame(0);
            end
            waits=0;
            while(!update && waits<500000) begin @(posedge clk); #1; waits=waits+1; end
            if(!update) $fatal(1,"CCL timeout scene %0d",scene);
            if(scene==4) begin
                if(!overflow || count!=0 || boxes!=0) $fatal(1,"Label overflow must invalidate results");
            end else begin
                if(overflow || count!=ec) $fatal(1,"Count scene=%0d got=%0d expected=%0d",scene,count,ec);
                // Allow ties to appear in either deterministic rank order.
                for(i=0;i<ec;i=i+1) begin
                    n=0;
                    // BFS validates CCL geometry/color/area, independently of the
                    // contour classifier tested by known rotated primitives.
                    for(j=0;j<ec;j=j+1) if((boxes[i*64 +:64] & ~(64'd3<<59))===(expected[j] & ~(64'd3<<59))) n=n+1;
                    if(n!=1) $fatal(1,"CCL/BFS box mismatch scene=%0d box=%h",scene,boxes[i*64 +:64]);
                    if(scene==8 && boxes[i*64+59 +:2]!=(boxes[i*64+61 +:2]==1 ? 1:3))
                        $fatal(1,"CCL seed/contour rotated rectangle and triangle");
                    if(scene==9 && boxes[i*64+59 +:2]!=2) $fatal(1,"CCL circle with internal gap");
                end
                if(scene==1 && boxes[60:59]!=2) $fatal(1,"Largest test disk must be a circle");
            end
            repeat(3) @(negedge clk);
        end
        // Interrupted capture and analysis must recover after reset.
        for(i=0;i<N;i=i+1) image[i]=1;
        send_frame(0); repeat(10) @(negedge clk); rst=0;
        repeat(3) @(negedge clk);
        if(count!=0 || boxes!=0 || update || busy) $fatal(1,"Detector reset");
        rst=1;
        for(i=0;i<N;i=i+1) image[i]=0;
        send_frame(0);
        wait(update); #1; if(count!=0 || overflow) $fatal(1,"Post-reset empty frame");
        $display("PASS: color CCL vs independent BFS, shapes, same-color separation, unions, ranking, borders, noise, overflow, busy drop and reset");
        $finish;
    end
    initial begin #15000000; $fatal(1,"Test timeout"); end
endmodule
