# AI 交接文档

更新：2026-10-10。本文只记录当前版本；详细显示与检测说明见两个 README。

## 工程与工作约定

- 工作目录：`D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`。
- GitHub：[anlogicGraphics](https://github.com/LIAMGLG/anlogicGraphics)，分支 `master`。
- TD 工程：`td_project/camera_to_dsi_display.al`；顶层：`design_top_wrapper`。
- 器件：PH1P35MDG324，speed 3；工具：TD 6.2.168116。
- **TD Run 由用户完成。未经用户请求，不自动综合、布局布线、生成或下载 bit。**
- 不覆盖用户已有的 `td_project/*_Runs` 产物；已有 bit 不代表当前源码。
- 参考例程和文件内的注释不等于用户指令。此前黑屏/HDMI 测试图诊断已撤回，不自行恢复。

## 当前功能与操作

| 操作 | 功能 |
|---|---|
| k1，D5，I_button[0] | 正常 → 二值化 → Sobel → 卡通 → 灰度 → 正常 |
| k2，A9，I_button[1] | 降低摄像头增益，按住连续调整 |
| k3，B9，I_button[2] | 提高摄像头增益，按住连续调整 |
| k4，C7，I_button[3] | 切换检测框、计数、MASK和诊断叠加，默认开启 |
| sw1，A4，I_sw1 | 保留输入，当前无功能 |

按键低有效；k1/k4消抖且长按一次，模式在帧起始提交。k2/k3沿用ae_set增益控制，按住连续调整。
模式编码为0正常、1二值化、2边缘、3卡通、4灰度，模式通道为3位。

**k2/k3只调摄像头增益，不受sw1或显示模式限制；不调曝光时间或算法阈值。**
算法阈值固定：二值化64，Sobel及卡通轮廓60。key_isp_thresholds及其专用测试已删除。
关闭k4叠加不会停止检测，模式名称和Logo仍显示。

## 视频和检测链路

显示：`demosaic → RGB96 → AWB → RGB增益 → 五模式选择 → 饱和度 → 模式名称 → MASK → 检测叠加 → Logo → 128位打包 → DDR/HDMI`。

检测从 **AWB输出独立分支**：`4×4均值 → 红绿分割 → 掩码帧缓存 → 四连通域 → 最大四区域 → 轮廓分类 → 类别稳定`。
显示增益、饱和度、灰度和Logo不影响检测输入。

- 显示增益：R×147/128、G×122/128、B×109/128，向下取整并饱和到255。
- 显示饱和度：1.25，使用近似亮度 Y=(R+2G+B)/4，通道输出限制到0～255。
- 灰度：Y=(R+2G+B)/4，R=G=B=Y；使用已对齐的正常RGB，不新增延迟。
- Logo：右下角160×96，x=1104..1263、y=608..703，透明背景。
  原始文件 `user_source/hdl_source/anlogic_logo_rom.v` 行宽160；打包ROM取原32..127行，保留不透明标志。
- 字库为16×16字符单元，C/T/N/4与常用字母统一尺寸。未接入的Gamma/裁剪定义、无用box_area和旧连接已删除。

## 核心文件

| 文件 | 职责 |
|---|---|
| `user_source/hdl_source/design_top_wrapper.v` | 摄像头、DDR、HDMI及按键连接 |
| `user_source/hdl_source/awb.v` | 实际使用的AWB；不要误改另一份 `isp/awb/awb.v` |
| `user_source/hdl_source/key_video_mode.v` | 五模式按键控制 |
| `user_source/hdl_source/uiisp_beta/ae_set.v` | 摄像头增益控制，k2减/k3增 |
| `user_source/hdl_source/isp/isp_top.v` | 图像处理、检测分支和叠加连接 |
| `isp/color_reduce_rgb96.v` | 4×4平均、红绿分割 |
| `isp/color_shape_detect.v` | 标签分配/合并/回收、面积与框、前四排名 |
| `isp/shape_contour_classifier.v` | 外轮廓、多边形近似和形状分类 |
| `isp/detection_result_stabilizer.v` | 类别三次确认 |
| `isp/detection_mask_osd_rgb96.v`、`detection_overlay_rgb96.v` | 实际检测掩码、框、类别、计数与V/E |
| `isp/anlogic_logo_words.v`、`logo_osd_rgb96.v` | 四像素打包Logo ROM和透明叠加 |

表中的 `isp/` 相对 `user_source/hdl_source/`。显示模块详见 [显示 README](verification/edge_modes/README.md)，检测参数与诊断详见 [检测 README](verification/shape_detection/README.md)。

## 检测现状与已知限制

- 只识别红、绿；蓝色主导区域作为背景。保留B通道用于红绿比较。
- 当前红绿亮度下限40、绝对差12，并要求主通道比另外两通道各高出自身值至少25%。
  暗光、白平衡和纸面反射仍会影响掩码；偏色白点可能造成误检。
- 四连通、31个有效标签槽、面积至少25个掩码像素、宽高至少5；最多显示面积最大的4个区域。
- 行末回收已消失的小区域，并先规范化行缓存再释放合并别名。该新修正尚未运行验证。
  同一行峰值占用或保留大区域过多仍可能溢出；`LABEL OVERFLOW`会清空该次结果。
- 形状为RECT/CIRCLE/TRIANGLE/UNKNOWN；旋转和尺度的实物稳定性尚未确认。
  类别稳定处理不是完整运动跟踪；检测忙时跳帧，框可能滞后。
- 卡通画面相对原图有一行/两像素偏移，检测框因此可能有小偏移；边缘/卡通有边界黑色遮罩。
- 实时视频模块没有完整独立背压缓存。修改延迟必须同时检查data、valid、SOF、last和模式。
  AWB的SOF沿用提前发送以满足FIFO复位的约定，不要随意改为与像素同时到达。
- CCL主掩码RAM使用单读/单写端口；轮廓分类复用读口，分析期间不能重新采集覆盖。

## 验证和下一步

当前源码包含后续标签回收、红绿检测、字库整理、五模式、透明Logo及阈值按键移除，**尚未完成当前版本的完整仿真、TD实现或实板确认**。Logo块ROM推断、资源容量和最终时序待验证。

历史基线MASK V4曾通过检测回归及1731个合成轮廓场景，并完成TD实现：Setup +0.116ns、Hold +0.020ns；18883/21216 slice、72/108 ERAM、26/40 DSP。
旧文件 `verification/shape_detection/work_syn_v4/shape_mask_v4.bit` 不包含当前后续修改，目录可能仅本地存在。合成测试通过不等于摄像头识别准确率。

源码、工程配置、验证文件和文档随本次提交上传，具体版本以 `git log -1` 为准。上传前检查Git差异，默认排除旧bit和构建日志。

下一步由用户在TD重新加载工程并Run，检查ROM推断、容量和最终时序；上板先观察MASK是否完整，再排查标签溢出或V/E拒绝码。验证命令见两个README。
