// Output-side OSD. Bounds: x=16..367, y=608..671. Numbers latch once per frame.
// CAP/DISP/AGE are decimal; LAT is milliseconds to 0.1 ms.
module latency_osd(
    input wire I_clk,I_rst_n,
    input wire [31:0] I_us,I_latest_id,
    input wire I_meta_valid,input wire [64:0] I_meta,
    input wire I_bad,
    input wire [10:0] I_reason,
    input wire I_vs,I_hs,I_de,input wire [23:0] I_rgb,
    output reg O_vs,O_hs,O_de,output reg [23:0] O_rgb,
    output reg O_measure_valid,
    output reg [31:0] O_latency_us,O_age,O_display_id
);
    reg vs_d,armed,meta_seen;
    reg [64:0] frame_meta;
    reg [11:0] x,y;
    reg de_d;
    // One shared binary-to-decimal converter: 32 cycles per value, 128/frame.
    reg [31:0] convert_shift;
    reg [39:0] convert_bcd;
    reg [39:0] latency_bcd,age_bcd,cap_bcd,disp_bcd;
    reg [1:0] convert_phase;
    reg [5:0] convert_left;
    reg [15:0] wait_reason;
    wire [15:0] display_reason=wait_reason | {5'd0,I_reason};
    reg [39:0] convert_adjust;
    integer n;
    wire [31:0] delta=I_us-frame_meta[31:0];
    wire [31:0] age=I_latest_id-frame_meta[63:32];
    always @(*) begin
        convert_adjust=convert_bcd;
        for(n=0;n<10;n=n+1) begin
            if(convert_bcd[n*4 +:4]>=5) convert_adjust[n*4 +:4]=convert_bcd[n*4 +:4]+4'd3;
        end
    end
    wire panel=I_de && x>=16 && x<368 && y>=608 && y<672;
    wire [4:0] col=(x-12'd16)>>4;
    wire [1:0] line=(y-12'd608)>>4;
    reg [7:0] ch;
    reg [3:0] digit;
    wire [15:0] glyph;
    wire text_valid=O_measure_valid && !I_bad && convert_left==0;
    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar=value<10 ? 8'h30+value : 8'h41+value-10;end
    endfunction
    always @(*) begin
        ch=" ";digit=0;
        if(line==0 || line==1) begin
            case(col)
                0: ch=line==0 ? "C" : "D";
                1: ch=line==0 ? "A" : "I";
                2: ch=line==0 ? "P" : "S";
                3: ch=line==0 ? " " : "P";
                16: ch="F";17: ch="R";
                default: begin
                    if(col>=5 && col<15) begin
                        digit=line==0 ? ((cap_bcd>>((14-col)*4)) & 4'hf) :
                                        ((disp_bcd>>((14-col)*4)) & 4'hf);
                        ch=8'h30+digit;
                    end
                end
            endcase
        end else if(line==2) begin
            case(col)
                0:ch="A";1:ch="G";2:ch="E";16:ch="F";17:ch="R";
                default: if(col>=5 && col<15) ch=8'h30+((age_bcd>>((14-col)*4)) & 4'hf);
            endcase
        end else begin
            case(col)
                0:ch="L";1:ch="A";2:ch="T";12:ch=".";
                13:ch=8'h30+latency_bcd[11:8];15:ch="M";16:ch="S";
                default: if(col>=5 && col<12) ch=8'h30+((latency_bcd>>((14-col)*4)) & 4'hf);
            endcase
        end
        if(!text_valid && col>=5) begin
            case(col) 5:ch="W";6:ch="A";7:ch="I";8:ch="T";default:ch=" ";endcase
            if(line==3 && col>=10 && col<14)
                ch=hexchar((display_reason>>((13-col)*4)) & 4'hf);
        end
    end
    osd_char_lib font(.I_char(ch),.I_row(y[3:0]),.O_row_bits(glyph));
    wire [15:0] row_bits=ch=="." ? ((y[3:0]==12 || y[3:0]==13) ? 16'h0180 : 16'd0) : glyph;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            vs_d<=0;de_d<=0;armed<=1;meta_seen<=0;frame_meta<=0;x<=0;y<=0;
            O_vs<=0;O_hs<=0;O_de<=0;O_rgb<=0;O_measure_valid<=0;
            O_latency_us<=0;O_age<=0;O_display_id<=0;
            convert_shift<=0;convert_bcd<=0;convert_phase<=0;
            latency_bcd<=0;age_bcd<=0;cap_bcd<=0;disp_bcd<=0;convert_left<=0;wait_reason<=0;
        end else begin
            vs_d<=I_vs;de_d<=I_de;
            O_vs<=I_vs;O_hs<=I_hs;O_de<=I_de;
            O_rgb<=panel ? (row_bits[15-x[3:0]] ? 24'h00ffff : 24'h101010) : I_rgb;
            if(!I_de) x<=0;else x<=x+1'b1;
            if(de_d && !I_de) y<=y+1'b1;
            if(vs_d && !I_vs) begin
                armed<=1;meta_seen<=0;y<=0;O_measure_valid<=0;
            end
            if(I_meta_valid) begin frame_meta<=I_meta;meta_seen<=1;end
            if(I_de && armed) begin
                armed<=0;O_display_id<=frame_meta[63:32];
                O_measure_valid<=meta_seen && frame_meta[64] && !I_bad && !delta[31] && !age[31];
                O_latency_us<=delta;O_age<=age;
                wait_reason<={1'b0,age[31],delta[31],!frame_meta[64],!meta_seen,I_reason};
                convert_shift<=I_latest_id;convert_bcd<=0;convert_phase<=0;convert_left<=32;
            end else if(convert_left!=0) begin
                if(convert_left==1) begin
                    case(convert_phase)
                        0: begin cap_bcd<={convert_adjust[38:0],convert_shift[31]};convert_shift<=O_display_id;end
                        1: begin disp_bcd<={convert_adjust[38:0],convert_shift[31]};convert_shift<=O_age;end
                        2: begin age_bcd<={convert_adjust[38:0],convert_shift[31]};convert_shift<=O_latency_us;end
                        3: latency_bcd<={convert_adjust[38:0],convert_shift[31]};
                    endcase
                    convert_bcd<=0;convert_phase<=convert_phase+1'b1;
                    convert_left<=convert_phase==3 ? 0 : 32;
                end else begin
                    convert_bcd<={convert_adjust[38:0],convert_shift[31]};
                    convert_shift<=convert_shift<<1;
                    convert_left<=convert_left-1'b1;
                end
            end
            if(I_bad) O_measure_valid<=0;
        end
    end
endmodule
