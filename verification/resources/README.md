# 资源与时序对比

更新：2026-10-20。报告均来自TD 6.2.168116、PH1P35MDG324 speed 3。

## 最新本地实现记录

2026-10-20 19:19:31资源报告及19:19:28时序报告：20315/21216 Slice（95.75%，余901）、19093 LUT6（89.99%）、22321寄存器（52.60%）、83 ERAM（76.85%）、26 DSP（65.00%）；SWNS +0.119 ns、HWNS +0.020 ns，STA coverage 95.19%。报告来源仍为本工程phy_1的camera_to_dsi_display_phy.area及final_timing.rpt。

综合层次包含u_red_rect_gimbal：490逻辑LUT、236 ripple、346寄存器、0 ERAM/0 DSP；其中u_pd为291/122/217，父子不可重复累计。物理Slice与综合分类不是简单相加关系。

本次仅摘录用户本地Run结果，不上传生成报告、bit或数据库，也未建立源码快照与bit哈希对应。全局时序转正不代替CDC第二同步级、稳定负载和未覆盖路径核查；当前仍有时钟混合扇出、局部布线等告警。云台控制与加速测试见[云台说明](../gimbal/README.md)。

以下为历史对比，不应将旧报告当作当前结果。

## 整机报告

| 版本 | Slice | LUT6 | 寄存器 | ERAM | DSP | SWNS / HWNS |
|---|---:|---:|---:|---:|---:|---:|
| 原始例程，2026-09-11 | 12390，58.40% | 10002 | 13396 | 39 | 8 | +1.242 / +0.020 ns |
| OSD/Logo参考例程，2026-09-10 | 14852，70.00% | 12669 | 13380 | 40 | 9 | 本次未核对 |
| move，无延迟面板，2026-10-11 11:33 | 19619，92.47% | 18378 | 18627 | 91 | 26 | +0.105 / +0.020 ns |
| 有延迟面板、RGB888 Logo，2026-10-11 11:51 | 19477，91.80% | 17797 | 20254 | 91 | 26 | +0.106 / +0.020 ns |
| 当前三色Logo，2026-10-11 12:38 | 19163，90.32% | 17827 | 20269 | 73 | 26 | +0.155 / +0.020 ns |

容量：21216 Slice/LUT6、42432寄存器、108 ERAM、40 DSP。寄存器与Slice不是一对一关系；模块逻辑LUT和加法器资源也不能简单相加得到物理Slice。

用户指定的OSD参考位于 `D:/Anlogic/TDproject/lab_ex3_osd_SC500_720P/lab_ex3_osd`。其2026-09-10 16:44实现报告包含OSD/Logo，`u_hdmi_mixer` 为2572逻辑LUT、85 ripple、246寄存器、0 ERAM、1 DSP；其中Logo ROM为54逻辑LUT。源码使用单像素HDMI叠加及非二次幂字形缩放除法。当前四像素检测叠加/标题/Logo模块分别为602/150/117逻辑LUT，范围不同，不能直接当严格A/B或资源下限。

2026-10-12 14:10标签RAM/OSD优化后的实现报告：18584 Slice（87.59%）、16939 LUT6（79.84%）、19737寄存器、75 ERAM、26 DSP，SWNS +0.127 ns、HWNS +0.020 ns；综合日志确认提取label_stats RAM。相对优化前整机少888 LUT6、579 Slice、532寄存器，多2 ERAM；相对带OSD参考例程，整机多4270 LUT6、3732 Slice、35 ERAM、17 DSP。整机差值包含摄像头配置、功能、综合和布局差异，不等于检测模块独立成本。

证据来自各本地工程 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_phy.area` 和 `final_timing.rpt`。原始例程位于 `lab_ex1_mipi_hdmi_SC520_origin/lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi`；move位于 `lab_ex1_mipi_hdmi_SC520_move`；当前工程位于 `lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi`。本次提交不更新这些本地生成报告，克隆中的历史报告不是当前结果。

## 最近一次实现的模块占用（本次优化前）

| 模块 | 逻辑LUT | 加法器资源（ripple） | 寄存器 | ERAM | DSP |
|---|---:|---:|---:|---:|---:|
| AWB，含两个除法器 | 2203 | 2292 | 6037 | 10 | 8 |
| 颜色/形状检测，含轮廓 | 2927 | 482 | 2670 | 10 | 17 |
| 其中轮廓分类 | 1358 | 402 | 1244 | 2 | 16 |
| MASK显示 | 200 | 10 | 215 | 21 | 1 |
| Logo叠加，含ROM | 115 | 0 | 209 | 2 | 0 |
| 延迟测量与OSD | 964 | 189 | 1647 | 0 | 0 |

包含关系不能重复累加。相比原例程，多出的DSP主要来自轮廓分类等检测运算；AWB两个除法器原例程已有。

Logo从20块ERAM降到2块，总ERAM因此91→73。压缩前后整机Slice减少314，但LUT略增，说明布局/打包也发生变化，不能把314个Slice全部视作Logo本身节省。

move与当前的AWB、CCL、轮廓、ISP连接及Logo叠加源码忽略CRLF差异后相同；当前增加延迟模块并压缩Logo，完整电路改变后优化和布局结果也变了。因此“无帧计数”版本Slice反而更高，不表示延迟模块没有开销。准确A/B应在相同三色Logo源码上仅开关延迟模块，再分别Run。

## 后续优化与约束

2026-10-12已完成的RTL修改：

- CCL的面积、边界和种子六组动态读写数组合并为32×60 bit同步存储，单读口/单写口；左右数据顺序读出，区域更新一次写回。取消别名统计清零的第二写口，以有效槽/根条件屏蔽旧值，复用槽完整覆盖。parent/color小表仍用寄存器。非背景像素比原来多两拍，背景从八拍普通路径缩至四拍；实际速度随场景变化。
- 字库直接由字符/行译码为16位，取消256位字形总线的动态行选择；保留全部39个字形。检测列表和模式标题改为直接字符译码，取消宽字符串动态选字；编号字形索引限制在4位列号，四像素共用纵向框判断，颜色计数在SOF锁存。显示布局、重叠优先级和视频延迟不变。
- Logo沿用已经实现的三色索引ROM，30720 bit、两拍叠加；不将历史已省下的18块ERAM计作本次新增收益。

修改者未运行TD；用户14:10实现已确认32×60统计表提取为RAM，并得到上述优化后资源及Setup/Hold。整机净减少888 LUT6不能全部归因于字库，模块级收益须核对层次报告。CDC约束、同步器层级和时钟均未修改，工程SDC中的req1/ack1入口例外保留，第二级仍需时序检查。

2026-10-12 ModelSim验证PASS：CCL独立BFS、1731轮廓场景、稳定器、逐像素OSD/MASK、720p检测ISP、五模式/标题、4096字库字符行组合、三色Logo和四组HDMI延迟回归。检测与显示编译/仿真0错误0警告；Logo仅有旧版ModelSim Starter建议容量提示。仿真不证明资源收益或新布局时序。

字库独立参考来自优化前完整39字形快照，遍历全部256字符×16行；复现：

```powershell
powershell -ExecutionPolicy Bypass -File verification/resources/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/shape_detection/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/logo/run_sim.ps1
```

三色Logo已经实现并验证。AWB专用除法器、轮廓运算复用及位宽压缩目前仅完成可行性检查，不列作已实现优化；减少标签或轮廓点容量会改变检测能力，不能直接作为等价压缩。

12:38报告setup/hold均为正，但19:10用户Run的HWNS又为−0.612 ns。现已修正像素时间邮箱第一级入口约束；同一布线数据库只读重算为+0.155 / +0.020 ns，尚未重新完整Run。见 [CDC检查](../cdc_constraints/README.md)。时序通过不代替CDC审查或实板准确率验证。
