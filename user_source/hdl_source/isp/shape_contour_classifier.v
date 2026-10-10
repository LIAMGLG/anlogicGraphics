// Serial Moore boundary walk and closed Douglas-Peucker polygon approximation.
// The mask is immutable until O_done. I_pixel is a one-cycle synchronous RAM
// response to O_address. All arithmetic is integer; no CPU or floating point.
module shape_contour_classifier #(
    parameter integer WIDTH=320,HEIGHT=180,POINT_BITS=11
)(
    input wire I_clk,I_rst_n,I_start,
    input wire [8:0] I_seed_x,I_min_x,I_max_x,
    input wire [7:0] I_seed_y,I_min_y,I_max_y,
    input wire [16:0] I_area,
    input wire [1:0] I_color,I_pixel,
    output reg [15:0] O_address,
    output reg O_done,
    output reg [1:0] O_shape,
    output reg [3:0] O_reason,O_vertices
);
    localparam IDLE=0,PROBE=1,WAIT_RAM=2,CHECK=3,FINISH_TRACE=4,
        POP=5,READ_A=6,WAIT_A=7,READ_B=8,WAIT_B=9,PREPARE=10,
        READ_P=11,WAIT_P=12,DISTANCE=13,SPLIT=14,DECIDE=15,
        ANGLE=16,ANGLE_CHECK=17,ANGLE_MULT=18,ANGLE_TOLERANCE=19,
        DISTANCE_MULT=20,DISTANCE_COMPARE=21,SQUARE=22,
        LINE_LENGTH=23,LINE_PRODUCT=24,LINE_TOLERANCE=25,CORNER_TOLERANCE=26;
    localparam POINTS=1<<POINT_BITS;
    reg [4:0] state;
    reg [8:0] sx,px,nx,minx,maxx;
    reg [7:0] sy,py,ny,miny,maxy;
    reg [1:0] color;
    reg [16:0] area;
    reg [2:0] direction,tries;
    reg [POINT_BITS:0] length;
    reg [POINT_BITS-1:0] far_index;
    reg [9:0] far_distance;
    reg [7:0] epsilon_q4;
    reg [POINT_BITS-1:0] point_address;
    reg [16:0] points[0:POINTS-1];
    reg [16:0] point_q;
    reg [POINT_BITS-1:0] stack_a[0:15],stack_b[0:15];
    reg [4:0] stack_size;
    reg [POINT_BITS-1:0] a_index,b_index,index,max_index;
    reg [8:0] ax,bx;
    reg [7:0] ay,by;
    reg signed [9:0] dx;
    reg signed [8:0] dy;
    reg [19:0] max_cross;
    reg [13:0] tolerance;
    reg [4:0] vertices;
    reg [16:0] vertex[0:15];
    reg signed [31:0] polygon_twice_area;
    reg [19:0] perimeter_q8;
    reg [3:0] corner;
    reg convex,rectangle_angles;
    reg signed [19:0] corner_cross,corner_dot;
    reg cross_negative,have_sign;
    reg [31:0] polygon_abs;
    reg [39:0] perimeter_squared;
    reg [39:0] square_acc,square_operand;
    reg [19:0] square_factor;
    reg [4:0] square_count;
    reg failed;
    reg cleanup;
    reg [13:0] corner_tolerance;
    reg [10:0] edge1_l1,edge2_l1;
    wire [6:0] short_limit=((epsilon_q4+9'd16)*3)>>4;
    integer k;
    reg [15:0] watchdog;
    integer xx,yy;
    reg neighbor_ok;
    reg [9:0] distance_from_seed;
    reg signed [9:0] point_dx;
    reg signed [8:0] point_dy;
    reg signed [19:0] cross_value;
    reg [19:0] cross_abs;
    reg signed [19:0] segment_area;
    reg [10:0] tolerance_length;
    reg [19:0] tolerance_product;
    wire [8:0] tolerance_scale={1'b0,epsilon_q4}+9'd8;
    wire [22:0] tolerance_times5={3'b0,tolerance_product}+{1'b0,tolerance_product,2'b0};
    function [10:0] octagonal_length;
        input signed [10:0] vx;
        input signed [9:0] vy;
        reg [10:0] ux,uy,hi,lo;
        begin
            ux=vx<0 ? -vx : vx;uy=vy<0 ? -vy : vy;
            hi=ux>uy ? ux : uy;lo=ux>uy ? uy : ux;
            // Approximate Euclidean length; max error < 7%, versus 41%
            // direction variation for |x|+|y|. No square root/divider.
            octagonal_length=hi+(((lo<<1)+lo)>>3);
        end
    endfunction
    wire [19:0] scale_q4=(perimeter_q8>>11)+(perimeter_q8>>13);
    reg [3:0] prev_corner,next_corner;
    reg signed [9:0] e1x,e2x;
    reg signed [8:0] e1y,e2y;
    reg signed [9:0] edge1x_d,edge2x_d,point_dx_d;
    reg signed [8:0] edge1y_d,edge2y_d,point_dy_d;
    reg signed [19:0] cross_d;
    wire [19:0] distance_cross=cross_d<0 ? -cross_d : cross_d;
    reg [10:0] corner_chord_l1;
    wire signed [10:0] chord_x=edge1x_d+edge2x_d;
    wire signed [9:0] chord_y=edge1y_d+edge2y_d;
    wire [10:0] chord_l1=octagonal_length(chord_x,chord_y);
    wire closing=nx==sx && ny==sy && length>2;
    wire point_write=(state==IDLE && I_start) || state==FINISH_TRACE ||
        (state==CHECK && I_pixel==color && !closing && length<POINTS-1);
    wire [POINT_BITS-1:0] point_write_address=state==IDLE ? {POINT_BITS{1'b0}} : length[POINT_BITS-1:0];
    wire [16:0] point_write_data=state==IDLE ? {I_seed_x,I_seed_y} :
        (state==CHECK ? {nx,ny} : {sx,sy});
    // One explicit read port and one explicit write port, with no array reset,
    // allow TD to infer ERAM rather than thousands of flip-flops/multiplexers.
    always @(posedge I_clk) begin
        point_q<=points[point_address];
        if(I_rst_n && point_write) points[point_write_address]<=point_write_data;
    end
    always @(*) begin
        xx=px;yy=py;
        case(direction)
            0:xx=px+1; 1:begin xx=px+1;yy=py+1;end
            2:yy=py+1; 3:begin xx=px-1;yy=py+1;end
            4:xx=px-1; 5:begin xx=px-1;yy=py-1;end
            6:yy=py-1; 7:begin xx=px+1;yy=py-1;end
        endcase
        neighbor_ok=xx>=minx && xx<=maxx && yy>=miny && yy<=maxy;
        distance_from_seed=(px>sx ? px-sx : sx-px)+(py>sy ? py-sy : sy-py);
        point_dx=$signed({1'b0,point_q[16:8]})-$signed({1'b0,ax});
        point_dy=$signed({1'b0,point_q[7:0]})-$signed({1'b0,ay});
        cross_value=dx*point_dy-dy*point_dx;
        cross_abs=cross_value<0 ? -cross_value : cross_value;
        segment_area=$signed({1'b0,ax})*$signed({1'b0,by})-
                     $signed({1'b0,bx})*$signed({1'b0,ay});
        prev_corner=corner==0 ? vertices-1'b1 : corner-1'b1;
        next_corner=corner==vertices-1'b1 ? 0 : corner+1'b1;
        e1x=$signed({1'b0,vertex[corner][16:8]})-$signed({1'b0,vertex[prev_corner][16:8]});
        e1y=$signed({1'b0,vertex[corner][7:0]})-$signed({1'b0,vertex[prev_corner][7:0]});
        e2x=$signed({1'b0,vertex[next_corner][16:8]})-$signed({1'b0,vertex[corner][16:8]});
        e2y=$signed({1'b0,vertex[next_corner][7:0]})-$signed({1'b0,vertex[corner][7:0]});
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;O_done<=0;O_shape<=0;O_address<=0;
            O_reason<=0;O_vertices<=0;
            sx<=0;sy<=0;px<=0;py<=0;nx<=0;ny<=0;minx<=0;maxx<=0;miny<=0;maxy<=0;
            area<=0;color<=0;direction<=0;tries<=0;length<=0;far_index<=0;far_distance<=0;
            epsilon_q4<=16;point_address<=0;stack_size<=0;a_index<=0;b_index<=0;index<=0;max_index<=0;
            tolerance_length<=0;tolerance_product<=0;
            ax<=0;ay<=0;bx<=0;by<=0;dx<=0;dy<=0;max_cross<=0;tolerance<=0;
            vertices<=0;polygon_twice_area<=0;perimeter_q8<=0;corner<=0;
            convex<=1;rectangle_angles<=1;corner_cross<=0;corner_dot<=0;
            cross_negative<=0;have_sign<=0;polygon_abs<=0;perimeter_squared<=0;failed<=0;watchdog<=0;
            cleanup<=0;corner_tolerance<=0;edge1_l1<=0;edge2_l1<=0;
            edge1x_d<=0;edge2x_d<=0;edge1y_d<=0;edge2y_d<=0;point_dx_d<=0;point_dy_d<=0;cross_d<=0;corner_chord_l1<=0;
            square_acc<=0;square_operand<=0;square_factor<=0;square_count<=0;
        end else begin
            O_done<=0;
            case(state)
                IDLE: if(I_start) begin
                    sx<=I_seed_x;sy<=I_seed_y;px<=I_seed_x;py<=I_seed_y;
                    minx<=I_min_x;maxx<=I_max_x;miny<=I_min_y;maxy<=I_max_y;
                    area<=I_area;color<=I_color;length<=1;
                    direction<=5;tries<=0;
                    far_index<=0;far_distance<=0;perimeter_q8<=0;failed<=0;watchdog<=0;
                    epsilon_q4<=16;
                    O_shape<=0;O_reason<=0;O_vertices<=0;vertices<=0;state<=PROBE;
                end
                PROBE: begin
                    if(watchdog==65535) begin failed<=1;O_reason<=2;state<=DECIDE;end
                    else begin
                        watchdog<=watchdog+1'b1;
                        if(neighbor_ok) begin
                            nx<=xx;ny<=yy;O_address<=yy*WIDTH+xx;state<=WAIT_RAM;
                        end else if(tries==7) begin failed<=1;O_reason<=2;state<=DECIDE;end
                        else begin direction<=direction+1'b1;tries<=tries+1'b1;end
                    end
                end
                WAIT_RAM:state<=CHECK;
                CHECK: begin
                    if(I_pixel==color) begin
                        perimeter_q8<=perimeter_q8+(direction[0] ? 20'd362 : 20'd256);
                        if(nx==sx && ny==sy && length>2) state<=FINISH_TRACE;
                        else if(length>=POINTS-1) begin failed<=1;O_reason<=3;state<=DECIDE;end
                        else begin
                            length<=length+1'b1;px<=nx;py<=ny;
                            direction<={direction[2:1],1'b0}+3'd7;tries<=0;state<=PROBE;
                            if((nx>sx ? nx-sx : sx-nx)+(ny>sy ? ny-sy : sy-ny)>far_distance) begin
                                far_distance<=(nx>sx ? nx-sx : sx-nx)+(ny>sy ? ny-sy : sy-ny);
                                far_index<=length[POINT_BITS-1:0];
                            end
                        end
                    end else if(tries==7) begin failed<=1;O_reason<=2;state<=DECIDE;end
                    else begin direction<=direction+1'b1;tries<=tries+1'b1;state<=PROBE;end
                end
                FINISH_TRACE: begin
                    // Continuous Q4 tolerance from contour perimeter, avoiding
                    // bounding-box changes during rotation and integer size bins.
                    epsilon_q4<=scale_q4<16 ? 8'd16 : (scale_q4>240 ? 8'd240 : scale_q4[7:0]);
                    stack_a[0]<=far_index;stack_b[0]<=length[POINT_BITS-1:0];
                    stack_a[1]<=0;stack_b[1]<=far_index;stack_size<=2;
                    vertex[0]<={sx,sy};vertices<=0;polygon_twice_area<=0;
                    state<=POP;
                end
                POP: begin
                    if(stack_size==0) begin
                        polygon_abs<=polygon_twice_area<0 ? -polygon_twice_area : polygon_twice_area;
                        square_acc<=0;square_operand<={20'd0,perimeter_q8};square_factor<=perimeter_q8;square_count<=20;
                        corner<=0;convex<=1;rectangle_angles<=1;have_sign<=0;
                        cleanup<=1;
                        if(vertices>=3 && vertices<=15) state<=SQUARE;
                        else begin failed<=1;O_reason<=7;state<=DECIDE;end
                    end else begin
                        a_index<=stack_a[stack_size-1'b1];b_index<=stack_b[stack_size-1'b1];
                        point_address<=stack_a[stack_size-1'b1];stack_size<=stack_size-1'b1;
                        state<=READ_A;
                    end
                end
                READ_A:state<=WAIT_A;
                WAIT_A:begin ax<=point_q[16:8];ay<=point_q[7:0];point_address<=b_index;state<=READ_B;end
                READ_B:state<=WAIT_B;
                WAIT_B:begin bx<=point_q[16:8];by<=point_q[7:0];state<=PREPARE;end
                PREPARE:begin
                    dx<=$signed({1'b0,bx})-$signed({1'b0,ax});
                    dy<=$signed({1'b0,by})-$signed({1'b0,ay});
                    index<=a_index+1'b1;max_cross<=0;max_index<=a_index;
                    state<=LINE_LENGTH;
                end
                LINE_LENGTH:begin tolerance_length<=octagonal_length(dx,dy);state<=LINE_PRODUCT;end
                LINE_PRODUCT:begin tolerance_product<=tolerance_scale*tolerance_length;state<=LINE_TOLERANCE;end
                LINE_TOLERANCE:begin tolerance<=tolerance_times5>>6;state<=READ_P;end
                READ_P:begin
                    if(index>=b_index) state<=SPLIT;
                    else begin point_address<=index;state<=WAIT_P;end
                end
                WAIT_P:state<=DISTANCE;
                DISTANCE:begin
                    point_dx_d<=point_dx;point_dy_d<=point_dy;state<=DISTANCE_MULT;
                end
                DISTANCE_MULT:begin
                    cross_d<=dx*point_dy_d-dy*point_dx_d;state<=DISTANCE_COMPARE;
                end
                DISTANCE_COMPARE:begin
                    if(distance_cross>max_cross) begin max_cross<=distance_cross;max_index<=index;end
                    index<=index+1'b1;state<=READ_P;
                end
                SPLIT:begin
                    if(max_cross>tolerance && max_index>a_index && max_index<b_index) begin
                        if(stack_size>13) begin failed<=1;O_reason<=4;state<=DECIDE;end
                        else begin
                            stack_a[stack_size]<=max_index;stack_b[stack_size]<=b_index;
                            stack_a[stack_size+1'b1]<=a_index;stack_b[stack_size+1'b1]<=max_index;
                            stack_size<=stack_size+2;state<=POP;
                        end
                    end else begin
                        if(vertices>=15) begin failed<=1;O_reason<=7;state<=DECIDE;end
                        else begin
                            vertex[vertices[3:0]]<={ax,ay};vertices<=vertices+1'b1;
                            polygon_twice_area<=polygon_twice_area+segment_area;state<=POP;
                        end
                    end
                end
                ANGLE:begin
                    edge1x_d<=e1x;edge1y_d<=e1y;edge2x_d<=e2x;edge2y_d<=e2y;state<=ANGLE_MULT;
                end
                ANGLE_MULT:begin
                    corner_cross<=edge1x_d*edge2y_d-edge1y_d*edge2x_d;
                    corner_dot<=edge1x_d*edge2x_d+edge1y_d*edge2y_d;
                    edge1_l1<=(edge1x_d<0 ? -edge1x_d : edge1x_d)+(edge1y_d<0 ? -edge1y_d : edge1y_d);
                    edge2_l1<=(edge2x_d<0 ? -edge2x_d : edge2x_d)+(edge2y_d<0 ? -edge2y_d : edge2y_d);
                    corner_chord_l1<=chord_l1;state<=ANGLE_TOLERANCE;
                end
                ANGLE_TOLERANCE:begin
                    tolerance_product<=tolerance_scale*corner_chord_l1;state<=CORNER_TOLERANCE;
                end
                CORNER_TOLERANCE:begin corner_tolerance<=tolerance_times5>>6;state<=ANGLE_CHECK;end
                ANGLE_CHECK:begin
                    if(cleanup) begin
                        // The arbitrary start/cut points of a closed contour can
                        // add near-collinear vertices. Remove them using the same
                        // distance tolerance before counting polygon corners.
                        if(vertices>3 && ((corner_cross<0 ? -corner_cross : corner_cross)<=corner_tolerance ||
                            (corner_dot>0 && corner_dot*2>(corner_cross<0 ? -corner_cross : corner_cross) &&
                            ((edge1_l1<=short_limit && edge2_l1>=edge1_l1*4) ||
                             (edge2_l1<=short_limit && edge1_l1>=edge2_l1*4))))) begin
                            for(k=0;k<15;k=k+1)
                                if(k>=corner && k<vertices-1) vertex[k]<=vertex[k+1];
                            vertices<=vertices-1'b1;corner<=0;state<=ANGLE;
                        end else if(corner==vertices-1'b1) begin cleanup<=0;corner<=0;state<=ANGLE;end
                        else begin corner<=corner+1'b1;state<=ANGLE;end
                    end else begin
                    if(corner_cross!=0) begin
                        if(have_sign && cross_negative!=(corner_cross<0)) convex<=0;
                        cross_negative<=corner_cross<0;have_sign<=1;
                    end else convex<=0;
                    // Interior angles 53..127 degrees tolerate mild perspective.
                    if((corner_dot<0 ? -corner_dot : corner_dot)*4 >
                       (corner_cross<0 ? -corner_cross : corner_cross)*3) rectangle_angles<=0;
                    if(corner==vertices-1'b1) state<=DECIDE;
                    else begin corner<=corner+1'b1;state<=ANGLE;end
                    end
                end
                DECIDE:begin
                    O_shape<=0;
                    O_vertices<=vertices>15 ? 4'd15 : vertices[3:0];
                    if(!failed) begin
                        if(minx==0 || miny==0 || maxx==WIDTH-1 || maxy==HEIGHT-1) O_reason<=1;
                        else if(!convex) O_reason<=5;
                        else if(area*32'd200<polygon_abs*32'd80) O_reason<=6;
                        else if(vertices==4 && !rectangle_angles) O_reason<=8;
                        else if(vertices>=5 && vertices<=12 && perimeter_squared>{3'b0,area,20'b0}) O_reason<=9;
                        else if(vertices<3 || vertices>12) O_reason<=7;
                        else O_reason<=0;
                    end
                    if(!failed && convex && area*32'd200>=polygon_abs*32'd80 &&
                       minx!=0 && miny!=0 && maxx!=WIDTH-1 && maxy!=HEIGHT-1) begin
                        if(vertices==3) O_shape<=3;
                        else if(vertices==4 && rectangle_angles) O_shape<=1;
                        else if(vertices>=5 && vertices<=12 &&
                            // Q8 chain perimeter: P^2 <= 16*A (~circularity >= pi/4).
                            // Compare by a shift; no divider or wide constant multiplier.
                            perimeter_squared<={3'b0,area,20'b0})
                            O_shape<=2;
                    end
                    O_done<=1;state<=IDLE;
                end
                SQUARE:begin
                    if(square_factor[0]) square_acc<=square_acc+square_operand;
                    square_operand<=square_operand<<1;square_factor<=square_factor>>1;
                    square_count<=square_count-1'b1;
                    if(square_count==1) begin
                        perimeter_squared<=square_acc+(square_factor[0] ? square_operand : 40'd0);
                        state<=ANGLE;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
