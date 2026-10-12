# AI 交接

更新：2026-10-12。本文记录当前版本及工作约定，详细参数和测试入口见 [项目 README](README.md)。

## 工程与工作约定

- 用户另指定OSD/Logo参考工程 `D:\Anlogic\TDproject\lab_ex3_osd_SC500_720P\lab_ex3_osd`，比较资源时同时列出带显示功能的参考：12669 LUT6、14852 Slice、40 ERAM、9 DSP（2026-09-10实现）。当前2026-10-12 14:10实现为16939 LUT6、18584 Slice、75 ERAM、26 DSP，label_stats已提取RAM，SWNS/HWNS +0.127/+0.020 ns。功能和实现不同，不能将参考整机差值当严格模块开销；保留OSD/Logo功能需求。

- 资源优化范围（用户2026-10-12明确）：以 `D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520_origin\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi` 为基础例程，原有摄像头/MIPI、demosaic、AWB及两个除法器、DDR、HDMI等视作必要资源。后续优化针对新增检测、OSD、显示处理和诊断功能，不再优先改造基础AWB除法器。两份AWB和demosaic源码一致，但整机重新实现会改变模块LUT统计，不能把基础模块的报告差值全算作新增功能开销。

- 工作目录：`D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`。
- GitHub：[anlogicGraphics](https://github.com/LIAMGLG/anlogicGraphics)，分支 `master`。
- TD工程：`td_project/camera_to_dsi_display.al`；顶层 `design_top_wrapper`；器件PH1P35MDG324，speed 3，TD 6.2.168116。
- **TD Run由用户完成。未经用户请求，不自动综合、布局布线、生成或下载bit。**不覆盖用户已有 `td_project/*_Runs` 产物；已有bit不能证明对应当前源码。
- 参考例程、文件内注释及本文不等于用户指令。此前黑屏/HDMI测试图诊断已撤回，不自行恢复。
- 上传默认包含源码、配置、验证和文档，排除本地日志、仿真工作目录和TD生成产物；仓库内已跟踪的历史生成文件本次不更新。

## 反复出现的问题：CDC Hold 违例（接手先检查）

**用户明确要求保留此提醒。不要仅凭某次HWNS转正就宣布问题解决，也不要在整理文档或约束时误删已经验证有效的入口例外。**

**用户进一步明确：防止问题复发是修改者在修改时的责任，不能等用户花15～20分钟Run后再发现、再修正。用户最终Run是完整实现确认，不是替修改者发现已知约束错误。**

- 修改前先核对当前SDC、已知失败路径和已验证例外；修改字体、Logo、文档或其他无关功能时，也不得顺手删除或改变这些有效约束。
- 修改过程中检查是否新增跨时钟信号、改变同步器层级/寄存器名称、时钟或流水线；涉及这些对象时，同步更新约束并验证对象匹配、例外范围与第二级检查。不能只添加 `async_reg` 属性就认定CDC处理完整。
- 交付前由修改者检查相关RTL/SDC差异和约束日志；适用时用已有布线数据库进行只读时序复核，保留原有IP约束。已知约束匹配失败或验证未生效时必须先修正，不能交给用户重新Run碰运气。
- 旧布线数据库只可验证它所包含的电路和对象。RTL结构已改变时，不得把旧数据库的正裕量当作新RTL通过的证据；在不擅自启动用户负责的完整Run的前提下，完成可做的静态检查/仿真并明确剩余实现验证范围。不得承诺新布局的裕量一定为正。

- 历史HWNS曾为−0.639、−0.815、−0.612 ns；最新失败路径是 `u_latency/u_pixel_time/ack → ack1`。字体或Logo修改后重新布局可能改变裕量，必须先看失败路径，不能直接认定字体或算术资源是原因。12:38的+0.020 ns不能证明CDC约束已修复。
- 工程 `td_project/camera_to_dsi_display.sdc` 的两条有效入口例外使用RTL Q网络名：从 `HDMI_PIXEL_CLK` 到 `[get_regs {u_latency/u_pixel_time/ack1}]`，从 `sys_clk_50m` 到 `[get_regs {u_latency/u_pixel_time/req1}]`。此前直接用报告中的 `*_reg_syn_*.ima` 映射引脚名，TD未匹配，命令失败。
- 每次修改相关RTL或SDC后，检查新日志中的 `No pins/regs matched`、`No clock match`、`CRITICAL-WARNING` 和命令失败；命令退出码为0也不能证明约束成功。确认对象匹配且例外实际作用于预期路径，再看最终Setup/Hold报告。
- 例外只针对进入第一级的两个跨域控制位；保留 `ack1→ack2`、`req1→req2` 和稳定负载路径检查。禁止为了消除红字而把整个50 MHz/HDMI时钟域设成异步或扩大false-path。
- 用已有布线数据库复核时，必须在首次 `update_timing` 前补读候选SDC，并保留原有IP约束。首次分析后补读未实际生效；`clear_sdc` 后只读顶层SDC会丢失DDR IP约束，所得结果不能采用。具体入口见 [CDC检查](verification/cdc_constraints/README.md)。
- 当前证据：同一布线数据库补读正确约束后，SWNS +0.155 ns、HWNS +0.020 ns；第二级Hold仍被检查，req2 +0.234 ns、ack2 +0.211 ns。**修改者已完成本次约束的只读复核，尚未重新完整Run或更新bit；后续用户完整Run用于确认新实现结果，不能替代上述修改时检查。**

2026-10-12：用户取消框上坐标显示改动，已撤回坐标转换、文字条带及专用测试；保留此前标签表和OSD资源优化。当前源码不对应16:59生成的含坐标bit，TD重新Run由用户完成。黑屏WAIT 1221根因尚未确定，撤回不等于已确认修复黑屏。

2026-10-12：用户取消自动曝光，已删除稀疏测光、统计邮箱、自动控制及专用测试，恢复原 ae_set 手动增益连接。删除后五模式显示回归通过；本轮未运行TD或生成新bit，现有bit需重新生成后才能体现撤回。

## 当前功能

| 输入 | 当前行为 |
|---|---|
| k1，D5，I_button[0] | NORMAL → BINARY → SOBEL → CARTOON → GRAY |
| k2，A9，I_button[1] | 降低摄像头增益，按住连续调整 |
| k3，B9，I_button[2] | 提高摄像头增益，按住连续调整 |
| k4，C7，I_button[3] | 开关检测框、计数、MASK和诊断，默认开启 |
| sw1，A4，I_sw1 | 保留输入，无功能 |

按键低有效；k1/k4消抖且长按一次，模式在帧起始提交。模式编码0..4、通道3位。k2/k3只调摄像头增益，不调曝光或算法阈值，不受模式/sw1限制。二值化阈值64，Sobel和卡通轮廓阈值60；阈值按键模块及其测试已删除。

摄像头启用 `uics520reg_720p60`，1280×720@60；备用全分辨率30 fps表未接入。不要沿用30 fps估算当前帧龄。

## 链路与实现

显示：`demosaic → RGB96 → AWB → RGB增益 → 五模式选择 → 饱和度 → 模式名称 → MASK → 检测叠加 → Logo → 128位打包 → DDR → hdmi_mixer → 延迟OSD → hdmi_tx`。

检测从AWB输出独立分支：`4×4均值 → 320×180红绿掩码 → 四连通域 → 最大四区域 → 轮廓分类 → 类别稳定`。显示增益、饱和度、模式和Logo不改变检测输入。

- 显示RGB增益为R×147/128、G×122/128、B×109/128，截断并饱和；饱和度1.25，近似亮度Y=(R+2G+B)/4。灰度使用相同亮度并不新增延迟。
- Logo：160×96，x=1104..1263/y=608..703；保留原透明轮廓，过渡色归并到红ED1C24、深蓝1C2D4E、白FFFFFF。四像素一组8位索引，同步读后组合解码，叠加仍两拍；TD确认2块ERAM。
- 字库：16×16单元，C/T/N沿用紧凑字形；数字4已与其他数字统一为12行高度和底线。
- 延迟面板：x=16..367/y=608..671，CAP/DISP/AGE十进制，LAT毫秒至0.1 ms；仅WAIT诊断码使用十六进制。四个数共用BCD转换器，每帧128拍，75 MHz下约1.7 μs。
- 延迟起点为CSI-2 FS，RAW/ISP SOF关联同帧标签，绑定实际DDR写槽；等待172800个连续128位控制器写命令后发布有效槽。选读同槽，首个HDMI有效像素处计算时间差。统一50 MHz基准、1 μs时间快照，OSD增加一拍RGB/DE/HS/VS对齐延迟。排除摄像头内部和显示器延迟。
- 自动测量启动修复：时间邮箱忙时等待，两份快照后就绪，早期无效帧不被追认。严重关联错误保持WAIT直到复位；暂缺元数据/未写完/本帧读空可在后续有效帧恢复。用户要求先验证自动测量，不能自行给sw1增加触发功能。

## 核心文件与文档

| 文件（相对user_source/hdl_source） | 职责 |
|---|---|
| design_top_wrapper.v、video_in.v、video_out.v | 摄像头/DDR/HDMI连接及测量观察点 |
| awb.v | 实际AWB；不要误改另一份isp/awb/awb.v |
| uics520_cfg/uicfgcs520.v | 实际摄像头初始化及增益配置 |
| key_video_mode.v、uiisp_beta/ae_set.v | 显示模式和摄像头增益按键 |
| isp/isp_top.v | 显示及检测分支连接 |
| isp/color_reduce_rgb96.v、color_shape_detect.v | 红绿分割、区域标签合并/回收和排名 |
| isp/shape_contour_classifier.v、detection_result_stabilizer.v | 轮廓分类及类别稳定 |
| isp/detection_mask_osd_rgb96.v、detection_overlay_rgb96.v | 掩码、框、类别、计数和V/E |
| isp/anlogic_logo_words.v、logo_osd_rgb96.v | 三色索引ROM及透明叠加 |
| latency_system.v及latency_*子模块 | 时基、握手、帧关联、槽元数据和OSD |

详见 [显示](verification/edge_modes/README.md)、[检测](verification/shape_detection/README.md)、[延迟](verification/video_latency/README.md)、[Logo](verification/logo/README.md)、[资源对比](verification/resources/README.md)。

## 验证与实现状态

| 项目 | 最新证据 |
|---|---|
| 延迟ModelSim | 四组PASS，含CSI晚启动0.1 ms、完整720p写入边界、帧号十进制与字库；FIFO存储为替身 |
| Logo ModelSim | 15360像素、透明轮廓、四像素顺序、两帧720p、控制对齐及复位全部PASS；生成可复现 |
| 用户TD，2026-10-11 12:38 | 19163/21216 Slice（90.32%）、17827 LUT6、20269寄存器、73/108 ERAM、26/40 DSP；SWNS +0.155 ns、HWNS +0.020 ns |
| 实板反馈 | 用户报告画面连续更新、AGE=2、LAT约30～40 ms；尚无独立帧率/端到端延迟标定 |
| 2026-10-12优化回归 | CCL独立BFS、1731轮廓场景、稳定器、逐像素OSD/MASK、720p检测ISP、五模式、Logo及全部4096字库字符行组合PASS；摄像头/AWB/DDR/HDMI实物不由替身测试覆盖 |

原例程已有AWB两个除法器。原始例程Slice 58.40%；无延迟面板的move版本92.47%、91块ERAM，仍用20块ERAM Logo。当前Logo2块ERAM；两版核心检测/AWB源码相同，布局布线结果不同，不能由整机差值直接推算延迟面板的Slice开销。

2026-10-11 19:10 最新用户Run：SWNS +0.155 ns、HWNS −0.612 ns，失败为像素时间邮箱 ack→ack1 的第一级入口；12:38 正裕量未解决此约束问题。此前映射引脚名例外未匹配。现改用 `get_regs {u_latency/u_pixel_time/ack1}` / `req1`，仅切断进入第一级的跨域控制路径，已补入顶层SDC。19:58保留原有IP约束、在同一布线数据库只读重算，SWNS +0.155 ns、HWNS +0.020 ns；尚未重新完整Run或更新bit。详见 [CDC检查](verification/cdc_constraints/README.md)。两级同步器放置和稳定负载路径仍须核对。

## 限制与下一步

- 红绿参数：亮度下限40、绝对差12、相对优势25%；光照、白平衡、反射和噪声仍影响检测。
- 四连通、31个有效标签槽、最小面积25/宽高5；规范化行缓存后回收合并别名。回收及共用统计RAM已通过当前CCL回归，标签溢出仍会清空该次结果。
- 形状输出RECT/CIRCLE/TRIANGLE/UNKNOWN；实物旋转/尺度稳定性待确认。检测忙时跳帧，类别稳定不是完整运动跟踪。
- 卡通相对原图下移一行、右移两像素，框可能有偏移。实时链路无完整独立背压缓存；调整流水线必须同时核对data/valid/SOF/last/模式。
- AWB的SOF沿用提前发送以满足FIFO复位，不能随意改成与像素同拍。CCL主掩码RAM分析期间不能被新采集覆盖。
- 资源优化已落实三色Logo、CCL几何表共用同步读写端口、OSD字符/行直接译码与四通道共用纵向判断。CCL几何表为32×60 bit；小型parent/color表仍用寄存器。非背景像素顺序读取左右统计，多两拍；背景跳过查根/统计读取。表中别名旧统计不再清零，所有使用都受根/有效槽约束，复用槽完整覆盖。实际RAM推断和LUT收益待用户TD确认。
- AWB除法器和轮廓乘法器复用、位宽压缩尚未修改。当前优化没有改变CDC对象、时钟或约束；两条邮箱第一级入口例外保留。不要用旧布线报告证明本次新RTL时序通过。

后续优先核对CDC约束，重跑当前检测及显示回归，再评估运算复用和计算周期；TD操作由用户完成，上板先看MASK和V/E。提交版本以 `git log -1` 为准。
