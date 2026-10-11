# Read-only checkpoint inspection; no synthesis, place, route, export_db or bitgen.
cd {D:/Anlogic/TDproject/lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi/verification/cdc_constraints/work}
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {D:/Anlogic/TDproject/lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
read_sdc {D:/Anlogic/TDproject/lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi/verification/cdc_constraints/pixel_time.sdc}
update_timing -mode final
report_timing_summary -file corrected.rpt
report_timing_path -file synchronizers.rpt -to [get_regs {u_latency/u_pixel_time/ack2 u_latency/u_pixel_time/req2}]
report_timing_exception -file exceptions.rpt
exit
