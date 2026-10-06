/*
按键翻转开关：每次按下翻转一次输出电平。

按键相对工作时钟是异步的，复用工程已有的 key_remove_shakes 完成同步与消抖，
每次按下产生一个时钟周期的高脉冲。新档位在 I_frame_start 处锁存，并且帧起始
那一拍就直接使用新档位，保证同一帧内档位一致。

I_key         低有效按键输入
I_frame_start 帧起始标志，需与 I_clk 同域
O_level       当前档位，复位后为 1
*/

module key_toggle(
	input wire I_clk,          
	input wire I_rst_n,        
	
	input wire I_key,          
	input wire I_frame_start,  
	
	output wire O_level        
);

	wire S_trig;   
	reg  S_req;    
	reg  S_level;  
	
	
	key_remove_shakes u_key_remove_shakes(
		.I_clk          ( I_clk   ),
		.I_rst_n        ( I_rst_n ),
		.I_key_in       ( I_key   ),
		.O_key_trig_out ( S_trig  )
	);
	
	
	//每次按下翻转请求档位
	always @(posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_req <= 1'b1;
		else if(S_trig)
			S_req <= ~S_req;
	end
	
	
	//档位在帧起始锁存
	always @(posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_level <= 1'b1;
		else if(I_frame_start)
			S_level <= S_req;
	end
	
	
	//帧起始那一拍直接用新档位，整帧保持一致
	assign O_level = I_frame_start ? S_req : S_level;

endmodule
