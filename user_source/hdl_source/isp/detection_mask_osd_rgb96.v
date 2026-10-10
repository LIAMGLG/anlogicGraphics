// Three-bank preview: capture cannot overwrite a completed mask awaiting SOF.
// Four two-bit mask pixels are packed per RAM word; one read and one write
// port. Publish the completed bank with detection results, latch it at SOF.
// Two-cycle RGB/control latency, independent of detector processing latency.
module detection_mask_osd_rgb96 #(
    parameter integer IMG_WIDTH=1280,MASK_WIDTH=320,MASK_HEIGHT=180,
    parameter integer PREVIEW_X=944,PREVIEW_Y=16,ADDRESS_BITS=14
)(
    input wire I_clk,I_rst_n,I_enable,
    input wire I_capture_valid,I_capture_done,I_result_update,
    input wire [8:0] I_x,
    input wire [7:0] I_y,
    input wire [1:0] I_color,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    localparam DEPTH=3*(1<<ADDRESS_BITS);
    reg [7:0] memory[0:DEPTH-1];
    reg [7:0] read_q;
    reg [5:0] pack;
    reg [1:0] write_bank,completed_bank,pending_bank,read_bank;
    reg pending,ready,enabled;
    wire capture_first=I_x==0 && I_y==0;
    wire [1:0] free_bank=(read_bank!=0 && completed_bank!=0) ? 2'd0 :
        ((read_bank!=1 && completed_bank!=1) ? 2'd1 : 2'd2);
    wire [1:0] capture_bank=I_capture_valid && capture_first ? free_bank : write_bank;
    wire result_ready=pending || I_result_update;
    wire [1:0] result_bank=I_result_update ? completed_bank : pending_bank;
    wire [1:0] frame_bank=I_tuser && result_ready ? result_bank : read_bank;
    wire frame_ready=I_tuser ? (ready || result_ready) : ready;
    wire frame_enable=I_tuser ? I_enable : enabled;
    wire [ADDRESS_BITS-1:0] write_word=I_y*(MASK_WIDTH/4)+(I_x>>2);
    wire [ADDRESS_BITS+1:0] write_address={capture_bank,write_word};
    reg [11:0] x;
    reg [10:0] y;
    wire [11:0] cx=I_tuser ? 12'd0 : x;
    wire [10:0] cy=I_tuser ? 11'd0 : y;
    wire in_preview=cx>=PREVIEW_X && cx<PREVIEW_X+MASK_WIDTH &&
        cy>=PREVIEW_Y && cy<PREVIEW_Y+MASK_HEIGHT;
    wire in_border=cx>=PREVIEW_X-4 && cx<PREVIEW_X+MASK_WIDTH+4 &&
        cy>=PREVIEW_Y-4 && cy<PREVIEW_Y+MASK_HEIGHT+4 && !in_preview;
    wire in_caption=cx>=PREVIEW_X && cx<PREVIEW_X+128 &&
        cy>=PREVIEW_Y+MASK_HEIGHT+12 && cy<PREVIEW_Y+MASK_HEIGHT+28;
    wire [11:0] local_x=cx-PREVIEW_X;
    wire [10:0] local_y=cy-PREVIEW_Y;
    wire [ADDRESS_BITS-1:0] read_word=in_preview ? local_y*(MASK_WIDTH/4)+(local_x>>2) : 0;
    wire [ADDRESS_BITS+1:0] read_address={frame_bank,read_word};
    reg [95:0] data_d,rendered;
    reg valid_d,user_d,last_d,preview_d,border_d,caption_d,ready_d;
    reg [3:0] column_d,row_d;
    reg [7:0] char_d;
    wire [15:0] glyph;
    wire [63:0] caption="MASK V4 ";
    integer lane;
    function [23:0] mask_rgb;
        input [1:0] c;
        begin case(c)
            1:mask_rgb=24'hff4040;
            2:mask_rgb=24'h40ff40;
            3:mask_rgb=24'h4080ff;
            default:mask_rgb=0;
        endcase end
    endfunction
    always @(posedge I_clk) begin
        if(I_rst_n && I_capture_valid && I_x[1:0]==3)
            memory[write_address]<={pack,I_color};
        read_q<=memory[read_address];
    end
    osd_char_lib u_font(.I_char(char_d),.I_row(row_d),.O_row_bits(glyph));
    always @(*) begin
        rendered=data_d;
        for(lane=0;lane<4;lane=lane+1) begin
            if(preview_d) rendered[95-lane*24 -:24]=ready_d ? mask_rgb(read_q[7-lane*2 -:2]) : 24'd0;
            if(border_d) rendered[95-lane*24 -:24]=24'hffffff;
            if(caption_d) rendered[95-lane*24 -:24]=glyph[15-(column_d+lane)] ? 24'hfff200 : 24'd0;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            pack<=0;write_bank<=0;completed_bank<=0;pending_bank<=0;read_bank<=2;
            pending<=0;ready<=0;enabled<=1;x<=0;y<=0;
            data_d<=0;valid_d<=0;user_d<=0;last_d<=0;preview_d<=0;border_d<=0;caption_d<=0;ready_d<=0;
            column_d<=0;row_d<=0;char_d<=0;O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            if(I_capture_valid) begin
                if(capture_first) write_bank<=capture_bank;
                if(I_x[1:0]==0) pack<={4'd0,I_color};
                else pack<={pack[3:0],I_color};
            end
            if(I_capture_done) completed_bank<=capture_bank;
            if(I_result_update) begin pending<=1;pending_bank<=completed_bank;end
            if(I_tuser) begin
                enabled<=I_enable;x<=0;y<=0;
                if(result_ready) begin read_bank<=result_bank;ready<=1;pending<=0;end
            end
            if(I_tvalid) begin
                if(I_tlast || cx==IMG_WIDTH-4) begin x<=0;y<=cy+1'b1;end
                else begin x<=cx+4;y<=cy;end
            end
            data_d<=I_tdata;valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tlast;
            preview_d<=frame_enable && in_preview;border_d<=frame_enable && in_border;
            caption_d<=frame_enable && in_caption;ready_d<=frame_ready;
            column_d<=local_x[3:0];row_d<=cy-(PREVIEW_Y+MASK_HEIGHT+12);
            char_d<=caption[63-local_x[6:4]*8 -:8];
            O_tdata<=rendered;O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;
        end
    end
endmodule
