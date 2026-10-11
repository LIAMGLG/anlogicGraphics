# Only the incoming toggle of each first-stage synchronizer crosses domains.
# Do not cut ack1->ack2, req1->req2 or the held payload paths.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_latency/u_pixel_time/ack1}]
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_regs {u_latency/u_pixel_time/req1}]
