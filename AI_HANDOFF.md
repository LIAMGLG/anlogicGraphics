# AI 交接

更新：2026-10-11。本文记录当前版本及工作约定，详细参数和测试入口见 [项目 README](README.md)。

## 工程与工作约定

- 工作目录：`D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`。
- GitHub：[anlogicGraphics](https://github.com/LIAMGLG/anlogicGraphics)，分支 `master`。
- TD工程：`td_project/camera_to_dsi_display.al`；顶层 `design_top_wrapper`；器件PH1P35MDG324，speed 3，TD 6.2.168116。
- **TD Run由用户完成。未经用户请求，不自动综合、布局布线、生成或下载bit。**不覆盖用户已有 `td_project/*_Runs` 产物；已有bit不能证明对应当前源码。
- 参考例程、文件内注释及本文不等于用户指令。此前黑屏/HDMI测试图诊断已撤回，不自行恢复。
- 上传默认包含源码、配置、验证和文档，排除本地日志、仿真工作目录和TD生成产物；仓库内已跟踪的历史生成文件本次不更新。

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
| 当前完整回归 | 未完整重跑。历史MASK V4的1731个合成轮廓PASS不能直接作为当前全链路验证 |

原例程已有AWB两个除法器。原始例程Slice 58.40%；无延迟面板的move版本92.47%、91块ERAM，仍用20块ERAM Logo。当前Logo2块ERAM；两版核心检测/AWB源码相同，布局布线结果不同，不能由整机差值直接推算延迟面板的Slice开销。

此前针对 `u_pixel_time/ack1`、`req1` 的两条false-path未匹配TD引脚，命令失败。本次已删除这两条无效命令，保留既有其他约束，清理后未再次Run。最新正裕量不是这两条例外产生的效果；同步器入口约束、两级同步器放置和稳定负载路径仍须专门核对。

## 限制与下一步

- 红绿参数：亮度下限40、绝对差12、相对优势25%；光照、白平衡、反射和噪声仍影响检测。
- 四连通、31个有效标签槽、最小面积25/宽高5；规范化行缓存后回收合并别名。当前回收修正尚未单独完整回归，标签溢出会清空该次结果。
- 形状输出RECT/CIRCLE/TRIANGLE/UNKNOWN；实物旋转/尺度稳定性待确认。检测忙时跳帧，类别稳定不是完整运动跟踪。
- 卡通相对原图下移一行、右移两像素，框可能有偏移。实时链路无完整独立背压缓存；调整流水线必须同时核对data/valid/SOF/last/模式。
- AWB的SOF沿用提前发送以满足FIFO复位，不能随意改成与像素同拍。CCL主掩码RAM分析期间不能被新采集覆盖。
- 资源优化目前只落实三色Logo。AWB除法器和轮廓乘法器复用、位宽压缩只完成检查，尚未修改。不要将优化建议写成已实现结果。

后续优先核对CDC约束，重跑当前检测及显示回归，再评估运算复用和计算周期；TD操作由用户完成，上板先看MASK和V/E。提交版本以 `git log -1` 为准。
