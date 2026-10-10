// Classical two-pass connected-component analysis of a reduced color mask.
// Four-connectivity, same-color union/find, bounded label capacity, no CNN.
// Retire completed undersized components and reclaim merged aliases after
// canonicalizing the entire row cache. Label capacity bounds live slots.
// Acquires a complete frame only while idle. Busy frames are skipped, never
// backpressure video. A single mask RAM is owned by capture OR analysis.
// Result record: valid[63],color[62:61],shape[60:59] (1=rect,2=circle,0=unknown),
// shape=3 triangle. xmin[58:48],ymin[47:38],xmax[37:27],ymax[26:17],area[16:0].
module color_shape_detect #(
    parameter integer WIDTH=320, HEIGHT=180,
    parameter integer LABEL_BITS=5,
    parameter integer MIN_AREA=25, MIN_WIDTH=5, MIN_HEIGHT=5
)(
    input wire I_clk, I_rst_n, I_valid,
    input wire [1:0] I_color,
    input wire [8:0] I_x,
    input wire [7:0] I_y,
    output reg [255:0] O_boxes,
    output reg [2:0] O_count,
    output reg O_overflow,
    output reg O_update,
    output wire O_busy,
    output wire O_capture_valid,O_capture_done,
    output reg [31:0] O_debug
);
    localparam LABELS=1<<LABEL_BITS;
    localparam IDLE=0, CLEAR=1, READ_PIXEL=2, WAIT_PIXEL=3, FIND_LEFT=4,
               FIND_TOP=5, APPLY=6, NEXT_PIXEL=7, SCAN=8, CLASSIFY=9, RANK=10, PUBLISH=11,
               FETCH=12, MEASURE=13, BOX_AREA=14, SHAPE_START=15, SHAPE_WAIT=16,
               ALLOC_FIND=17, ALLOC_COMMIT=18, RETIRE_BEGIN=19, RETIRE_FIND=20,
               RETIRE_FETCH=21, RETIRE_TEST=22, RETIRE_NEXT=23,
               CANON_READ=24, CANON_WRITE=25, RECLAIM_ALIASES=26;
    reg [4:0] state;
    reg capturing;
    reg [1:0] mask [0:WIDTH*HEIGHT-1];
    reg [1:0] mask_q;
    reg [LABEL_BITS-1:0] row_labels [0:WIDTH-1];
    reg [LABEL_BITS-1:0] top_q;
    reg [LABEL_BITS-1:0] parent [0:LABELS-1];
    reg [1:0] color [0:LABELS-1];
    reg [16:0] area [0:LABELS-1];
    reg [8:0] xmin [0:LABELS-1], xmax [0:LABELS-1];
    reg [7:0] ymin [0:LABELS-1], ymax [0:LABELS-1];
    reg [8:0] seedx [0:LABELS-1];
    reg [LABEL_BITS:0] allocated, scan;
    reg [LABELS-1:0] in_use;
    reg [LABEL_BITS:0] alloc_probe,retire_index;
    reg [LABEL_BITS-1:0] alloc_slot,retire_root;
    reg [7:0] retire_y,retire_maxy;
    reg [8:0] canon_x;
    reg [16:0] retire_area;
    reg [8:0] x;
    reg [7:0] y;
    reg [15:0] address;
    reg [LABEL_BITS-1:0] left_label, left_root, top_root;
    reg [1:0] pixel_color;
    reg overflow;
    reg [63:0] best [0:3];
    reg [8:0] best_seed [0:3];
    reg [8:0] left_seed,top_seed,current_seed;
    reg [1:0] shape_index;
    wire [63:0] shape_box=best[shape_index];
    wire [15:0] shape_address;
    wire shape_done;
    wire [1:0] contour_shape;
    wire [3:0] contour_reason,contour_vertices;
    reg [31:0] shape_debug;
    shape_contour_classifier #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_contour (
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==SHAPE_START && shape_box[63]),
        .I_seed_x(best_seed[shape_index]),.I_seed_y(shape_box[47:40]),
        .I_min_x(shape_box[58:50]),.I_max_x(shape_box[37:29]),
        .I_min_y(shape_box[47:40]),.I_max_y(shape_box[26:19]),
        .I_area(shape_box[16:0]),.I_color(shape_box[62:61]),.I_pixel(mask_q),
        .O_address(shape_address),.O_done(shape_done),.O_shape(contour_shape),
        .O_reason(contour_reason),.O_vertices(contour_vertices));
    reg [2:0] count;
    reg [9:0] bw;
    reg [8:0] bh;
    reg [18:0] box_area;
    reg [63:0] candidate;
    reg [16:0] left_area,top_area,current_area;
    reg [8:0] left_minx,left_maxx,top_minx,top_maxx,current_minx,current_maxx;
    reg [7:0] left_miny,top_miny,current_miny,current_maxy;
    reg [1:0] current_color;
    reg current_root;
    integer k;
    wire first=I_x==0 && I_y==0;
    wire last=I_x==WIDTH-1 && I_y==HEIGHT-1;
    wire accept=I_valid && (first ? state==IDLE : capturing);
    assign O_busy=state!=IDLE;
    assign O_capture_valid=accept;
    assign O_capture_done=accept && last;
    wire [15:0] capture_address=I_y*WIDTH+I_x;
    wire [15:0] mask_read_address=state==READ_PIXEL ? address : shape_address;
    wire mask_read_enable=state==READ_PIXEL || state==SHAPE_START || state==SHAPE_WAIT;
    // Synchronous RAM ports, deliberately outside reset loops for block RAM inference.
    always @(posedge I_clk) begin
        if(accept) mask[capture_address]<=I_color;
        if(mask_read_enable) mask_q<=mask[mask_read_address];
        if(state==READ_PIXEL) top_q<=row_labels[x];
        if(state==CANON_READ) top_q<=row_labels[canon_x];
        // All parents were flattened by RETIRE before this pass. No label is
        // allocated or reclaimed until every row reference has been rewritten.
        if(state==CANON_WRITE) row_labels[canon_x]<=parent[top_q];
        if(state==APPLY) begin
            if(pixel_color==0) row_labels[x]<=0;
            else if(left_root!=0) row_labels[x]<=left_root;
            else if(top_root!=0) row_labels[x]<=top_root;
            else row_labels[x]<=0;
        end
        if(state==ALLOC_COMMIT) row_labels[x]<=alloc_slot;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE; capturing<=0; O_boxes<=0; O_count<=0; O_overflow<=0; O_update<=0;
            O_debug<=0;shape_debug<=0;
            allocated<=0; scan<=0; x<=0; y<=0; address<=0;
            in_use<=0;alloc_probe<=0;alloc_slot<=0;retire_index<=0;retire_root<=0;
            retire_y<=0;retire_maxy<=0;retire_area<=0;canon_x<=0;
            left_label<=0; left_root<=0; top_root<=0; pixel_color<=0;
            overflow<=0; count<=0; bw<=0; bh<=0; box_area<=0; candidate<=0;
            left_seed<=0;top_seed<=0;current_seed<=0;shape_index<=0;
            left_area<=0;top_area<=0;current_area<=0;
            left_minx<=0;left_maxx<=0;top_minx<=0;top_maxx<=0;current_minx<=0;current_maxx<=0;
            left_miny<=0;top_miny<=0;current_miny<=0;current_maxy<=0;current_color<=0;current_root<=0;
            for(k=0;k<4;k=k+1) begin best[k]<=0;best_seed[k]<=0;end
        end else begin
            O_update<=0;
            if(I_valid && first) capturing<=state==IDLE;
            if(accept && last) begin
                capturing<=0; state<=CLEAR; scan<=0; allocated<=0; overflow<=0;
                x<=0; y<=0; address<=0; left_label<=0; count<=0;
                shape_debug<=0;
                for(k=0;k<4;k=k+1) best[k]<=0;
            end
            case(state)
                IDLE: ;
                CLEAR: begin
                    in_use[scan[LABEL_BITS-1:0]]<=0;
                    parent[scan[LABEL_BITS-1:0]]<=scan[LABEL_BITS-1:0];
                    area[scan[LABEL_BITS-1:0]]<=0; color[scan[LABEL_BITS-1:0]]<=0;
                    xmin[scan[LABEL_BITS-1:0]]<=0; xmax[scan[LABEL_BITS-1:0]]<=0;
                    ymin[scan[LABEL_BITS-1:0]]<=0; ymax[scan[LABEL_BITS-1:0]]<=0;
                    seedx[scan[LABEL_BITS-1:0]]<=0;
                    if(scan==LABELS-1) state<=READ_PIXEL;
                    else scan<=scan+1'b1;
                end
                READ_PIXEL: state<=WAIT_PIXEL;
                WAIT_PIXEL: begin
                    pixel_color<=mask_q;
                    left_root<=left_label;
                    top_root<=y==0 ? {LABEL_BITS{1'b0}} : top_q;
                    state<=FIND_LEFT;
                end
                FIND_LEFT: begin
                    if(left_root!=0 && parent[left_root]!=left_root) left_root<=parent[left_root];
                    else begin
                        if(left_root!=0 && color[left_root]!=pixel_color) left_root<=0;
                        state<=FIND_TOP;
                    end
                end
                FIND_TOP: begin
                    if(top_root!=0 && parent[top_root]!=top_root) top_root<=parent[top_root];
                    else begin
                        if(top_root!=0 && color[top_root]!=pixel_color) top_root<=0;
                        state<=FETCH;
                    end
                end
                FETCH: begin
                    left_area<=area[left_root]; top_area<=area[top_root];
                    left_minx<=xmin[left_root];left_maxx<=xmax[left_root];left_miny<=ymin[left_root];
                    top_minx<=xmin[top_root];top_maxx<=xmax[top_root];top_miny<=ymin[top_root];
                    left_seed<=seedx[left_root];top_seed<=seedx[top_root];
                    state<=APPLY;
                end
                APPLY: begin
                    state<=NEXT_PIXEL;
                    if(pixel_color==0) left_label<=0;
                    else if(left_root!=0) begin
                        left_label<=left_root;
                        if(top_root!=0 && top_root!=left_root) begin
                            parent[top_root]<=left_root;
                            area[left_root]<=left_area+top_area+1'b1;
                            area[top_root]<=0;
                            xmin[left_root]<=left_minx<top_minx ? left_minx : top_minx;
                            xmax[left_root]<=x>top_maxx ? (x>left_maxx ? x : left_maxx) :
                                              (top_maxx>left_maxx ? top_maxx : left_maxx);
                            ymin[left_root]<=left_miny<top_miny ? left_miny : top_miny;
                            seedx[left_root]<=left_miny<top_miny ? left_seed :
                                (top_miny<left_miny ? top_seed : (left_seed<top_seed ? left_seed : top_seed));
                            ymax[left_root]<=y;
                        end else begin
                            area[left_root]<=left_area+1'b1;
                            if(x>left_maxx) xmax[left_root]<=x;
                            ymax[left_root]<=y;
                        end
                    end else if(top_root!=0) begin
                        left_label<=top_root;
                        area[top_root]<=top_area+1'b1;
                        if(x<top_minx) xmin[top_root]<=x;
                        if(x>top_maxx) xmax[top_root]<=x;
                        ymax[top_root]<=y;
                    end else begin alloc_probe<=1;state<=ALLOC_FIND;end
                end
                ALLOC_FIND:begin
                    if(!in_use[alloc_probe[LABEL_BITS-1:0]]) begin
                        alloc_slot<=alloc_probe[LABEL_BITS-1:0];state<=ALLOC_COMMIT;
                    end else if(alloc_probe==LABELS-1) begin
                        overflow<=1;left_label<=0;state<=NEXT_PIXEL;
                    end else alloc_probe<=alloc_probe+1'b1;
                end
                ALLOC_COMMIT:begin
                    in_use[alloc_slot]<=1;parent[alloc_slot]<=alloc_slot;
                    if(alloc_slot>allocated) allocated<=alloc_slot;
                    left_label<=alloc_slot;color[alloc_slot]<=pixel_color;area[alloc_slot]<=1;
                    xmin[alloc_slot]<=x;xmax[alloc_slot]<=x;ymin[alloc_slot]<=y;ymax[alloc_slot]<=y;
                    seedx[alloc_slot]<=x;state<=NEXT_PIXEL;
                end
                NEXT_PIXEL: begin
                    if(x==WIDTH-1) begin
                        x<=0; y<=y+1'b1; left_label<=0;
                    end else x<=x+1'b1;
                    address<=address+1'b1;
                    if(address==WIDTH*HEIGHT-1) begin scan<=1; state<=SCAN; end
                    else if(x==WIDTH-1) begin
                        retire_y<=y;retire_index<=1;state<=RETIRE_BEGIN;
                    end else state<=READ_PIXEL;
                end
                // A four-connected component absent from this completed row
                // can never reconnect in a later row. Release only undersized
                // components, resolving every alias before reuse. Parent links
                // stay intact throughout retirement; allocations happen later.
                RETIRE_BEGIN:begin
                    if(retire_index>allocated) begin canon_x<=0;state<=CANON_READ;end
                    else if(in_use[retire_index[LABEL_BITS-1:0]]) begin
                        retire_root<=retire_index[LABEL_BITS-1:0];state<=RETIRE_FIND;
                    end else state<=RETIRE_NEXT;
                end
                RETIRE_FIND:begin
                    if(parent[retire_root]!=retire_root) retire_root<=parent[retire_root];
                    else state<=RETIRE_FETCH;
                end
                RETIRE_FETCH:begin
                    retire_area<=area[retire_root];retire_maxy<=ymax[retire_root];state<=RETIRE_TEST;
                end
                RETIRE_TEST:begin
                    parent[retire_index[LABEL_BITS-1:0]]<=retire_root;
                    if(retire_maxy<retire_y && retire_area<MIN_AREA) begin
                        in_use[retire_index[LABEL_BITS-1:0]]<=0;
                        if(retire_index==retire_root) area[retire_root]<=0;
                    end
                    state<=RETIRE_NEXT;
                end
                RETIRE_NEXT:begin retire_index<=retire_index+1'b1;state<=RETIRE_BEGIN;end
                CANON_READ:state<=CANON_WRITE;
                CANON_WRITE:begin
                    if(canon_x==WIDTH-1) begin retire_index<=1;state<=RECLAIM_ALIASES;end
                    else begin canon_x<=canon_x+1'b1;state<=CANON_READ;end
                end
                RECLAIM_ALIASES:begin
                    if(retire_index>allocated) state<=READ_PIXEL;
                    else begin
                        // Live roots retain geometry, area and seed. An alias
                        // owns no area and now has no references from the row
                        // cache or any other live parent; its slot is reusable.
                        if(in_use[retire_index[LABEL_BITS-1:0]] &&
                           parent[retire_index[LABEL_BITS-1:0]]!=retire_index[LABEL_BITS-1:0]) begin
                            in_use[retire_index[LABEL_BITS-1:0]]<=0;
                            area[retire_index[LABEL_BITS-1:0]]<=0;
                        end
                        retire_index<=retire_index+1'b1;
                    end
                end
                SCAN: begin
                    if(scan>allocated || overflow) begin
                        shape_index<=0;state<=overflow || count==0 ? PUBLISH : SHAPE_START;
                    end
                    else begin
                        current_area<=area[scan[LABEL_BITS-1:0]];
                        current_minx<=xmin[scan[LABEL_BITS-1:0]];current_maxx<=xmax[scan[LABEL_BITS-1:0]];
                        current_miny<=ymin[scan[LABEL_BITS-1:0]];current_maxy<=ymax[scan[LABEL_BITS-1:0]];
                        current_color<=color[scan[LABEL_BITS-1:0]];
                        current_seed<=seedx[scan[LABEL_BITS-1:0]];
                        current_root<=in_use[scan[LABEL_BITS-1:0]] && parent[scan[LABEL_BITS-1:0]]==scan[LABEL_BITS-1:0];
                        state<=MEASURE;
                    end
                end
                MEASURE: begin
                    bw<={1'b0,current_maxx}-{1'b0,current_minx}+1'b1;
                    bh<={1'b0,current_maxy}-{1'b0,current_miny}+1'b1;
                    state<=BOX_AREA;
                end
                BOX_AREA: begin
                    if(current_root && current_area>=MIN_AREA && bw>=MIN_WIDTH && bh>=MIN_HEIGHT) begin
                        box_area<=bw*bh;state<=CLASSIFY;
                    end else begin scan<=scan+1'b1;state<=SCAN;end
                end
                CLASSIFY: begin
                    candidate<={1'b1,current_color,2'b00,
                        current_minx,2'b00,current_miny,2'b00,
                        current_maxx,2'b11,current_maxy,2'b11,current_area};
                    state<=RANK;
                end
                RANK: begin
                    if(count<4) count<=count+1'b1;
                    if(candidate[16:0]>best[0][16:0]) begin
                        best[3]<=best[2]; best[2]<=best[1]; best[1]<=best[0]; best[0]<=candidate;
                        best_seed[3]<=best_seed[2];best_seed[2]<=best_seed[1];best_seed[1]<=best_seed[0];best_seed[0]<=current_seed;
                    end else if(candidate[16:0]>best[1][16:0]) begin
                        best[3]<=best[2]; best[2]<=best[1]; best[1]<=candidate;
                        best_seed[3]<=best_seed[2];best_seed[2]<=best_seed[1];best_seed[1]<=current_seed;
                    end else if(candidate[16:0]>best[2][16:0]) begin
                        best[3]<=best[2]; best[2]<=candidate;best_seed[3]<=best_seed[2];best_seed[2]<=current_seed;
                    end else if(candidate[16:0]>best[3][16:0]) begin best[3]<=candidate;best_seed[3]<=current_seed;end
                    scan<=scan+1'b1; state<=SCAN;
                end
                SHAPE_START:begin
                    if(shape_box[63]) state<=SHAPE_WAIT;
                    else state<=PUBLISH;
                end
                SHAPE_WAIT:if(shape_done) begin
                    best[shape_index][60:59]<=contour_shape;
                    shape_debug[shape_index*8 +:8]<={contour_vertices,contour_reason};
                    if(shape_index==3 || shape_index==count-1'b1) state<=PUBLISH;
                    else begin shape_index<=shape_index+1'b1;state<=SHAPE_START;end
                end
                PUBLISH: begin
                    O_boxes<=overflow ? 256'd0 : {best[3],best[2],best[1],best[0]};
                    O_count<=overflow ? 3'd0 : count;
                    O_overflow<=overflow; O_update<=1; state<=IDLE;
                    O_debug<=overflow ? 32'd0 : shape_debug;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
