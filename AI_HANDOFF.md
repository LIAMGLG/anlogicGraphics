# AI 交接文档

更新日期：2026-10-06。本文记录当前实现和用户已确认的要求，供后续 AI 接手；参考例程中的注释不等于用户的新指令。

## 工程与版本

- 仓库：https://github.com/LIAMGLG/anlogicGraphics.git，分支 master。
- 当前工作目录：D:\Anlogic\TDproject\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi。
- TD 工程：td_project/camera_to_dsi_display.al；顶层 design_top_wrapper。
- 器件：PH1P35MDG324，speed 3；工具 TD 6.2.168116。
- 前一功能提交：69b871b（四种模式及卡通化）。包含本文的新提交增加运行时阈值和 sw1 使能；具体提交号用 git log -1 查看。
- 本次上传包含源码、工程清单/引脚约束、仿真和文档。TD 运行产物的本地改动未纳入本次提交；不要把已有 bit 文件直接视为对应本次源码。

## 用户明确要求与现状

1. 图像算法单独模块化。已有正常、二值化、边缘、卡通四模式。
2. 上电和复位默认正常显示。
3. k1 始终切换：正常(0) → 二值化(1) → 边缘(2) → 卡通(3) → 正常。
4. k2 调二值化 threshold，默认 64，每次 +16；到 255 后下一次归零。序列 64、80、…、240、255、0、16、…。
5. k3 调 edge_th，默认 60，每次 +20；到 400 后下一次归零。该阈值同时影响边缘和卡通轮廓。
6. 用户已澄清：sw1 高电平才启用 k2/k3 的 ISP 阈值调试，k1 始终有效；sw1 低电平保留当前阈值。
7. 模式切换保留阈值，复位恢复 64/60；没有掉电保存。按键低有效、有消抖、长按只触发一次；参数在下一帧起始生效。
8. 用户反馈正常画面偏冷。尚未改白平衡、红蓝增益、Gamma；用户明确说先不管色差。此前建议的 R×1.10、B×0.90 仅为讨论，没有实现。
9. 偶发整屏短暂黑屏/重新同步曾做诊断，用户认为不明显并要求恢复。新增的彩条/HDMI TPG 诊断改动已撤回，不要自行恢复这项工作。

## 按键和开关引脚

| 用户称呼 | 顶层端口 | 管脚 | 功能 |
| --- | --- | --- | --- |
| k1 | I_button[0] | D5 | 四模式循环 |
| k2 | I_button[1] | A9 | threshold +16（sw1 高时） |
| k3 | I_button[2] | B9 | edge_th +20（sw1 高时） |
| 第四按键 | I_button[3] | C7 | 本次未新增功能 |
| sw1 | I_sw1 | A4 | 高电平允许 ISP 调参 |

约束在 user_source/constraints_source/pin.adc。sw1 使用 LVCMOS33、PULLUP。
用户提供的参考文件为 D:\Anlogic\TDproject\2_Example\8_key_sw\key_sw.adc 和 key_test.v；参考约束中 key[4] 为 A4，按第一路开关映射到 sw1。参考文件未修改，也未复制入仓库；物理开关编号未另做上板验证。

## 核心代码与链路

- user_source/hdl_source/design_top_wrapper.v：摄像头/DDR/HDMI 顶层，连接三个按键及 I_sw1 到 isp_top。
- user_source/hdl_source/isp/isp_top.v：demosaic → RGB 打包转换 → AWB → 四路图像处理 → 输出打包。正常输出为 AWB 后 RGB888，非灰度。
- user_source/hdl_source/awb.v：工程实际使用的 AWB；isp/awb/awb.v 是另一份代码，不能误改为当前实现。
- user_source/hdl_source/key_video_mode.v：消抖并在帧起始提交显示模式，RESET_MODE=0。
- user_source/hdl_source/key_isp_thresholds.v：阈值控制。BIN_RESET=64、EDGE_RESET=60、BIN_STEP=16、EDGE_STEP=20、EDGE_MAX=400；二值化溢出先饱和到 255，再按归零。
- sw1 经两级寄存器同步进入 ISP 时钟域；两个按键消抖器始终运行，只门控消抖事件对阈值请求寄存器的修改，不门控时钟。关闭期间已产生的按键事件不会在重新启用后补触发。
- user_source/hdl_source/isp/binary_threshold_96.v：四像素 RGB888 二值化。灰度近似 R/4+G/2+B/4，比较 >= threshold。
- user_source/hdl_source/isp/edge_detect_96.v：Sobel，采用两像素采样。I_edge_th 与梯度一起寄存，避免跨帧时旧梯度使用新阈值。
- 两算法均新增 DYNAMIC_THRESHOLD 参数，默认 0 保留常量参数用法；isp_top 置 1 接入运行时阈值。
- user_source/hdl_source/isp/cartoon_96.v：相邻两像素 RGB 平均后，每通道量化为 0/85/170/255（最多 64 色），复用 Sobel 掩码画黑轮廓。12×320 位颜色行缓存对齐 Sobel 窗口中心。
- 边缘输出延迟两拍；正常、二值化及模式寄存器延迟两拍保持对齐。修改流水线时必须一起检查 data、valid、SOF、行结束和模式。
- isp_top.v 末尾有 axis_gamma_rgb96、axis_crop_rgb96 定义，但当前 ISP 未实例化它们。
- key_isp_thresholds.v 已加入 .al 工程清单，CompileOrder=61。

## 已知限制，后续不要遗漏

- **k2/k3 仍同时接到原有 ae_set 的摄像头增益按键**：顶层 .I_btn({I_button[2],I_button[1],2'b11})，运行在 S_24m_clk 域。本次 sw1 仅门控 ISP 阈值调整，没有改 ae_set。因此调阈值时仍可能改变摄像头增益，sw1 低电平也仍可能调增益。已向用户说明。若下一步要实现 ISP 调参/摄像头增益互斥，先按用户后续意图确定，再在相应时钟域同步使能，避免直接异步门控。
- 卡通相对原图向下平移一行、向右平移两个像素，首行及每行首组四像素为黑色，末行/末像素对内容未完整输出。边缘模式保留原有首两行和行首遮罩。
- 卡通不是完整分辨率的双边滤波/去噪算法。
- threshold=0 时二值化全白；threshold=255 时全黑（当前近似灰度最大 253）。edge_th=0 时有效窗口均判为边缘，卡通相应区域会涂黑，这是 >= 判定的结果。
- 实时视频链路沿用原工程约定，算法模块没有完整的独立背压缓存；不要只改 ready 就宣称支持任意 AXI 停顿。

## 验证结果与复现

ModelSim 10.3c，默认位置 C:\altera\14.1\modelsim_ase\win32aloem。
在工程根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
```

脚本支持 -ModelSimBin，检查各项 PASS 标志，不仅检查进程退出码。本次四项均通过：

- tb_edge_modes.sv：Sobel 数值参考、动态阈值与梯度延迟、边界、valid 间隔、SOF、复位、真实按键消抖和四模式切换。
- tb_cartoon.sv：量化、黑轮廓、颜色/窗口中心对齐、连续像素、间隔和帧边界。
- tb_runtime_thresholds.sv：sw1 高低使能、关闭时保持、关闭期间按键事件不补触发、已长按后开启不重复触发、独立/同时按键、上限、回零、帧提交、默认值及全部 256 个二值化阈值。
- tb_isp_modes.sv：使用 demosaic/AWB 仿真替身检查四路输出选择和两拍控制延迟、连续输入和相邻帧；sw1 低电平接入。

这些仿真不覆盖真实摄像头、完整 AWB 除法、DDR 或 HDMI。

本次 sw1 版本已用 TD 完成全工程展开、RTL 和门级综合，含引脚/时钟约束。门级估计 Setup WNS=+0.684 ns、Hold WNS=+0.114 ns，setup/hold 违例数均为 0。存在原工程 RAM 未驱动引脚等综合警告，不能把成功表述为零警告。
本次没有执行完整布局布线、生成新 bit 或上板验证；上述估计不能替代最终布线时序。
本地 verification/edge_modes/check_synthesis.tcl 和 build_check.prj 可用于综合检查，它们是临时生成且被忽略的文件，GitHub 新克隆不能假设已有。新机器直接打开 .al 工程重新运行 TD 综合/布局布线/生成 bit。

## 接手建议

先读本文件和 verification/edge_modes/README.md，再查 git status、git log，明确源码与本地生成文件是否匹配。不要 git reset/clean 或覆盖用户已有产物。
用户本次要求是上传 GitHub 并写交接文档；后续没有自动修改色差、继续闪屏排查或改变增益按键的授权。
需要上板时重新加载工程清单，完成布局布线、检查最终时序、生成并下载对应 bit，再确认开关高低电平与三个按键效果。