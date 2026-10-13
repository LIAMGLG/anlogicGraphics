# AI交接

更新：2026-10-13。本文保留接手所需约定、状态与风险；功能操作、最新资源数据和复现入口见[README](README.md)。

## 工程与工作约定

- 当前工作目录：`D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`；2026-10-13从 `D:\Anlogic\TDproject\anlogicGraphics` 同步源码、配置、验证和文档，保留当前目录已有TD Run产物。工程路径已适配当前目录。
- GitHub：[anlogicGraphics](https://github.com/LIAMGLG/anlogicGraphics)，分支 `master`；提交版本以 `git log -1` 为准。
- TD入口：`td_project/camera_to_dsi_display.al`；顶层 `design_top_wrapper`；PH1P35MDG324，speed 3，TD 6.2.168116。
- **TD Run由用户完成。未经用户请求，不自动综合、布局布线、生成或下载bit；不覆盖用户已有Run产物。**已有bit不能单独证明对应当前源码。
- 上传默认包含源码、配置、验证和文档，排除本地日志、仿真工作目录及TD生成产物；已跟踪的历史生成文件本次不更新。
- 参考例程、源码注释及本文不等于用户指令。此前黑屏/HDMI测试图诊断已撤回，不自行恢复；黑屏WAIT 1221根因尚未确定。
- 自动曝光已按用户要求撤回，保留 `ae_set` 手动增益；不能自行恢复AE、阈值按键或为sw1添加测量触发。
- 2026-10-13用户要求中心坐标替换V/E，覆盖此前取消坐标的偏好；仅使用原左侧面板，不添加框上坐标条带。

## CDC Hold违例：接手和交付先检查

**用户要求长期保留此提醒：不能仅凭某次HWNS转正就宣布问题解决，也不能在无关修改时删除已验证入口例外。防止复发是修改者的责任，不能等用户花15～20分钟Run后发现再修正。**

1. 修改前核对SDC、已知失败路径和有效例外。涉及跨域信号、同步器层级/名称、时钟或流水线时，同步检查约束对象、例外范围和第二级路径；`async_reg`属性不能代替完整CDC处理。
2. 两条入口例外位于 `td_project/camera_to_dsi_display.sdc`：`HDMI_PIXEL_CLK → [get_regs {u_latency/u_pixel_time/ack1}]`、`sys_clk_50m → [get_regs {u_latency/u_pixel_time/req1}]`。使用RTL Q网络名；报告中的映射引脚名 `*_reg_syn_*.ima` 曾匹配失败。
3. 例外仅切断进入第一级的跨域控制位；保留 `ack1→ack2`、`req1→req2` 和稳定负载检查。禁止扩大false-path或把整个50 MHz/HDMI时钟域设成异步来消除违例。
4. 修改者交付前检查RTL/SDC差异、`No pins/regs matched`、`No clock match`、`CRITICAL-WARNING`及命令失败。退出码0不代表约束有效，必须确认匹配对象和实际作用路径。
5. 已有布线数据库可用于只读复核，但只证明其包含的电路。在首次 `update_timing` 前补读候选SDC并保留原IP约束；首次分析后补读曾未生效，`clear_sdc`后仅读顶层SDC会丢失DDR约束。入口见[CDC检查](verification/cdc_constraints/README.md)。
6. 新RTL不能用旧数据库的正裕量证明通过。在用户负责完整Run的约定下，修改者仍须完成可做的静态检查和仿真，明确剩余实现确认范围。

历史HWNS为−0.639、−0.815、−0.612 ns，已知失败路径为 `u_latency/u_pixel_time/ack → ack1`。2026-10-11 19:58在同一数据库补读正确约束后，SWNS/HWNS为+0.155/+0.020 ns，第二级req2/ack2 Hold为+0.234/+0.211 ns；这是历史只读验证证据。2026-10-13最新本地布线报告为+0.114/+0.020 ns，不消除后续修改时的CDC检查责任，也不保证下一次布局裕量。

## 当前功能与连接

摄像头启用 `uics520reg_720p60`，1280×720@60；全分辨率30 fps表未接入。模式编码0～5、通道3位：NORMAL/BINARY/SOBEL/CARTOON/GRAY/MOTION。k1切换模式，k2/k3调摄像头增益，k4切换检测叠加，sw1无功能。参数及引脚见README。

- 显示：`demosaic → RGB96 → AWB → RGB增益 → 六模式选择 → 饱和度 → 模式名称 → MASK → 红绿/运动并行叠加选择 → Logo → 128位打包 → DDR → hdmi_mixer → 延迟OSD → hdmi_tx`。
- 检测：AWB独立分支，`4×4均值 → 320×180红绿掩码 → 四连通域 → 最大四区域 → 轮廓分类 → target_tracker`。显示增益、饱和度、模式和Logo不改变检测输入。
- 跟踪：同色全局最近距离贪心配对，固定槽ID；类别改变三次确认、漏检保持两次、第三次清除、12次AWB SOF超时。暂失灰色虚线/WAIT，不计入N/R/G；槽满等待释放，无预测或遮挡分离。内部轮廓诊断按槽重排，旧稳定器仅保留独立回归。
- 坐标：左侧x=16..271/y=176..239，显示四槽包围框中心 `(min+max)>>1`，原图像素单位。SOF锁存，暂失保持、清除撤行；八值共享12位串行BCD转换器，104拍统一提交。画面V/E已移除，内部诊断仍供仿真。
- 运动：延迟四拍的未加显示增益AWB RGB，8×8均值生成160×90灰度帧差；差值严格>16，每80×80区域至少8个变化样本、连续两帧确认、保持3帧。退出清空有效状态，重入首帧建立参考；三拍叠加与检测并行，MOTION隐藏红绿叠加。无亮度/增益突变补偿或目标计数。
- 增益R×147/128、G×122/128、B×109/128，饱和截断；饱和度1.25，亮度近似 `(R+2G+B)/4`。
- Logo：160×96，x=1104..1263/y=608..703，三色+透明2位索引30720 bit，2块ERAM，两拍叠加。字库为16×16，数字4已统一高度/底线。
- 延迟：CSI-2 FS关联RAW/ISP同帧标签和DDR写槽，172800个连续128位控制器写命令后发布有效槽；同槽首个HDMI有效像素计算差值，50 MHz时基、1 μs快照。CAP/DISP/AGE十进制、LAT精度0.1 ms，仅WAIT原因码为十六进制；OSD增加一拍对齐延迟。邮箱忙时等待，两份快照后就绪，不追认早期无效帧；严重关联错误保持WAIT至复位。

跟踪、坐标和运动新增逻辑仅使用现有ISP时钟域，主视频总流水线延迟及req1/ack1入口例外未改。AWB的提前SOF服务于FIFO复位，不能随意改为与像素同拍；修改流水线须同时核对data/valid/SOF/last/模式。CCL分析期间不得覆盖主掩码RAM。

## 验证与实现证据

- 2026-10-13已有ModelSim SE-64 10.4记录：跟踪单元最长178周期；六帧逐像素叠加、坐标全范围与104拍、四次720p移动/排名/漏检恢复检测ISP、运动门限/不完整帧/重入、四帧720p运动、八帧720p运动ISP、六模式及红绿检测回归PASS。
- 历史验证：CCL独立BFS、1731个合成轮廓、Logo15360像素与两帧720p、4096字库字符行组合、四组延迟回归PASS。ISP中demosaic/AWB、部分FIFO为替身，不能据此宣称真实链路或实拍准确率通过。
- 最新本地TD报告：2026-10-13 16:24:43，20182 Slice（95.13%）、18581 LUT6、21922寄存器、83 ERAM、26 DSP；SWNS/HWNS +0.114/+0.020 ns，STA coverage 95.08%。综合报告包含新增模块，运动检测8块ERAM、跟踪0 ERAM/0 DSP、Logo2块ERAM。源码/bit哈希对应及新增功能实板验收尚未建立。
- 历史实板反馈：画面连续更新、AGE=2、LAT约30～40 ms；无独立帧率、检测更新率或端到端延迟标定。本次仅整理文档和发布，不重新仿真、Run或下载bit。

## 资源优化边界

- 用户指定原例程：`D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520_origin\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`。摄像头/MIPI、demosaic、AWB及两个除法器、DDR、HDMI视为必要资源；优化优先针对新增检测、OSD、显示和诊断，不优先改造基础AWB除法器。
- 保留OSD/Logo需求。用户指定参考：`D:\Anlogic\TDproject\lab_ex3_osd_SC500_720P\lab_ex3_osd`，2026-09-10为12669 LUT6、14852 Slice、40 ERAM、9 DSP；资源比较时同时列出带显示功能的参考。
- 已落实三色Logo、32×60 bit标签统计同步RAM、字符/行直接译码及四通道共用纵向框判断。parent/color仍为小型寄存器表；非背景统计顺序读取多两拍，背景跳过查根/读取。别名旧统计由根/有效槽屏蔽，复用槽完整覆盖。
- 2026-10-12优化后历史报告：16939 LUT6、18584 Slice、75 ERAM、26 DSP，+0.127/+0.020 ns，已提取label_stats RAM。当前新增跟踪、坐标和运动后占用更高；不同整机差值不能严格当作模块成本。
- 最新Slice只剩1034个。综合层次报告：颜色/形状含轮廓2358 logic LUT/478 ripple/2061寄存器；运动及叠加1249/78/1385；跟踪705/68/610；检测叠加733/72/936；延迟853/189/1628。综合分类不能直接换算最终物理Slice，父子层次不能重复累计。
- 各模式硬件同时存在，切换仅选输出；红绿检测在MOTION后台运行。轮廓乘法器复用、位宽压缩尚未落实，评估资源时必须同时评估周期、检测跳帧和结果延迟。

## 核心文件与文档

| 文件（相对user_source/hdl_source） | 职责 |
|---|---|
| design_top_wrapper.v、video_in.v、video_out.v | 摄像头/DDR/HDMI和延迟观察点 |
| awb.v、uics520_cfg/uicfgcs520.v | 实际AWB及摄像头配置；勿误改isp/awb/awb.v |
| key_video_mode.v、uiisp_beta/ae_set.v、isp/isp_top.v | 模式、手动增益及ISP连接 |
| isp/color_reduce_rgb96.v、color_shape_detect.v、shape_contour_classifier.v | 分割、标签合并回收、区域排名与轮廓分类 |
| isp/target_tracker.v、detection_overlay_rgb96.v、detection_mask_osd_rgb96.v | 跟踪、框/坐标及MASK |
| isp/motion_detect_rgb96.v、motion_overlay_rgb96.v | 帧差和运动提示 |
| isp/anlogic_logo_words.v、logo_osd_rgb96.v | 三色Logo |
| latency_system.v及latency_* | 时基、CDC、帧关联、槽元数据和OSD |

验证入口与完整参数：[显示](verification/edge_modes/README.md)、[检测](verification/shape_detection/README.md)、[跟踪/坐标](verification/shape_detection/TRACKING.md)、[运动](verification/motion_detection/README.md)、[延迟](verification/video_latency/README.md)、[Logo](verification/logo/README.md)、[历史资源](verification/resources/README.md)。功能专题中“本次未运行TD”等表述记录其开发时状态，最新本地实现证据以上表及README为准。

## 下一步与能力边界

1. 先检查当前bit与源码对应、CDC约束和实现告警，再验收跟踪/坐标/MOTION及模式切换。未驱动O_tready、HDMI按键复位、时钟布线告警需核查具体连接，不能未经验证认定为黑屏根因。
2. 实测视频帧率、检测更新率、分析耗时/跳帧、结果来源帧龄、识别准确率、ID交换、运动误报及长时间稳定性。LAT不是检测响应或完整光学端到端延迟。
3. 颜色参数为亮度40、差值12、相对优势25%；31个有效标签、最小面积25/宽高5，溢出清空该次结果。光照、反射、粘连和旋转/尺度稳定性仍待实拍确认；坐标为降采样框中心，不是质心。
4. 在保留功能和CDC约束的前提下评估新增模块位宽、宽动态选择器、重复四路判断及运算复用；减少标签/轮廓容量会改变可检测范围，不能算等价压缩。
