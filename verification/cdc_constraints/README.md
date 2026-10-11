# HDMI 时间邮箱的 CDC 约束检查

2026-10-11 19:10 用户 Run：SWNS +0.155 ns、HWNS −0.612 ns，唯一 Hold 失败终点为 `u_latency/u_pixel_time/ack1`。此前 12:38 的 +0.020 ns 是一次布局结果，未解决入口约束问题。

两个时钟仍属原有时钟组。邮箱用两级寄存器同步请求/应答，负载保持至应答返回；本次仅对进入 ack1、req1 的跨域控制位添加 false-path，不切断第二级或负载路径。

TD 的 `get_regs` 使用 RTL 寄存器 Q 网络名称。之前使用映射报告中的 `*_reg_syn_*.ima` 引脚未匹配；本次使用 `u_latency/u_pixel_time/ack1` 和 `req1`，已补入工程 SDC。

## 验证边界

本机 TD 6.2.168116，导入已有 `camera_to_dsi_display_pr.db`，在第一次 `update_timing` 前补读 `pixel_time.sdc`。不执行综合、布局布线、导出数据库、生成或下载 bit。保留数据库中的原有 IP 约束；不可 `clear_sdc` 后仅重读顶层 SDC，那会丢失 DDR IP 约束。

19:58 同一布线数据库重算：SWNS +0.155 ns、HWNS +0.020 ns、STNS/HTNS 0。日志没有约束匹配失败。19:59复核第二级仍被分析：req1→req2 Setup/Hold +12.574/+0.234 ns，ack1→ack2 +19.285/+0.211 ns。两级映射在同一物理单元的 oqa→imb，终点网络明确为 req2/ack2。仅修改分析约束，因此不能替代下一次完整 Run 或 CDC 亚稳态/负载稳定性审查；原有 bit 未更新。

`query.tcl` 是当前机器路径的只读复核入口，`pixel_time.sdc` 是独立候选约束。输出位于忽略目录 `work/`；`baseline.rpt` 保留未添加例外的 −0.612 ns，`corrected.rpt` 为补读后的结果，`synchronizers.rpt` 检查 ack2/req2，不能将早期清空约束的试验结果当作工程结论。
