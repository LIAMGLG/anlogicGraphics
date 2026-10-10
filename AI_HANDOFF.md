# AI 交接文档

## 2026-10-10：回收大目标内部的合并别名

用户反馈掩码几乎无小点，但圆/三角/旋转矩形仍 LABEL OVERFLOW。
检查发现 V4 只释放已经消失的不足 MIN_AREA 的小区域，合并到大目标的旧标签一直占槽。
因此实际限制仍包含大目标的历史别名，不只是同时存在的区域数量。
新增行末 CANON_READ/WRITE 两状态，将全部 row_labels 改成已解析的最终根；
之后 RECLAIM_ALIASES 扫描释放 in_use 且 parent!=self 的别名槽，保留根的面积/框/seed。
顺序为解析/扁平化所有父链→同步行缓存读写→别名释放→下一行分配，避免悬空引用。
保持 31 个槽及四连通定义，不增加标签 RAM 数量；每行增加 2*WIDTH+扫描槽数的周期。
同一行内同时占用超出容量、以及保留的大根过多仍会真实溢出；没有隐藏溢出告警。
补充三色重复分裂再合并到同一大区域样例，累计分配超过 31、并发仅少量，BFS核对面积/框。
按用户要求未运行仿真或 TD；尚不能认定上板问题已全部解决。最终时序也未验证。

## 2026-10-10：抑制偏色白点

用户反馈白色容易变成绿色小点并触发 LABEL OVERFLOW。
color_reduce_rgb96 在 4×4 RGB 平均后，将每个颜色的有效通道差改为
max(COLOR_MARGIN,ceil(主通道/4))，仍要求主通道>=COLOR_MIN 且胜过另外两个通道。
保留原默认 MIN=80、MARGIN=32，增加至少 25% 的相对通道优势条件，三色对称。
例如 (200,238,200) 以前判 GREEN，现在判背景；(168,224,168) 仍判 GREEN。
只增加移位、比较和加法，不增 RAM、流水线拍数或标签容量。
此判据也可能排除浅色目标，不能保证强烈偏色白背景或全部噪声都被抑制。
tb_color_reduce 已补三色偏白拒绝、彩绿保留及相对阈值边界样例，并同步独立参考。
按用户要求未运行仿真或 TD，实际掩码效果和时序需要用户 Run 后验证。

## 2026-10-10：检测与显示颜色调整分离

用户反馈现在只有红色能检测。发现此前检测使用 gain_data，固定增益提高 R、压低 G/B，
而分割阈值仍是 COLOR_MIN=80、COLOR_MARGIN=32，因此可能抑制蓝绿色的有效掩码。
已将 u_color_reduce 的 data/valid/SOF/last 全部改接 AWB 原始输出，
显示继续使用 RGB 增益和 1.25 饱和度。检测不再受这两项显示调整影响。
没有盲目降低阈值，避免碎点增多引起 LABEL OVERFLOW；需要用户确认 MASK 小窗表现。
此项为源码修正，未运行 TD/仿真或上板验证，不能保证已解决所有蓝绿检测问题。
本节取代下文“检测使用固定增益后的 RGB”的旧连接描述。

## 2026-10-10：显示饱和度 1.25

用户同意饱和度 1.25，只作用于显示，检测继续使用固定增益后的 RGB。
新增 saturation_rgb96.v，接在四模式选择后、模式名称 OSD 前，避免改变文字/框/掩码颜色。
使用近似亮度 Y=floor((R+2G+B)/4)，输出 clip(floor((5C-Y)/4),0,255)。
四像素并行，移位加减实现；数据、valid、SOF、last 和模式一起延迟两拍。
灰阶保持不变，黑白显示不变；原检测输入和参数保持不变。工程清单已加入模块。
按用户要求没有运行 TD 或生成 bit；本次饱和度尚未运行仿真/时序验证。

## 2026-10-10：固定 RGB 增益

用户要求增加 R×147/128、G×122/128、B×109/128。
新增 isp/color_gain_rgb96.v，接在 AWB 输出后，四像素并行，整数除法向下取整，
红色超过 255 饱和；使用移位加减实现。数据、valid、SOF、last 同步延迟两拍。
正常/二值化/Sobel/卡通化和颜色检测统一使用增益后的 RGB，按键参数在增益后的 SOF 提交。
TD 工程 .al 已加入模块，edge_modes 与 shape_detection 的 ISP 仿真编译清单已更新。
增益全 256 灰阶、四通道像素位置、饱和、间隔、复位和显示联动测试通过（edge_modes 六项）。
用户明确要求自行在 TD 中 Run；已停止本次自动 TD 构建，未生成新的可下载 bit，
后续默认只修改源码，由用户在 TD 中综合、布局布线和生成 bit。现有 V4 bit 不含本次增益。


## 2026-10-09 后续：MASK V4 小连通域标签回收

用户上板 V3 后确认掩码正确但无框，并明确 HDMI 显示 LABEL OVERFLOW。
已定位到 CCL：此前全帧累计分配最多 31 个临时标签，面积筛选前的碎点也占用标签，
溢出时清空整帧结果；不是形状分类 UNKNOWN 本身阻止画框。

color_shape_detect.v 新增标签使用位图、空闲槽分配、行末退休扫描。
四连通域在本行完全消失后不可能再接上未来行；若其面积不足 MIN_AREA，
解析所有父标签后回收该区域的根和合并别名。退休期间不重新分配标签，
保留父链直到扫描完成，避免复用后旧别名指向新目标；有效目标仍保留统计信息。
最终扫描忽略空闲槽；保留原始掩码、最小面积、四连通性和轮廓分类。
标签容量仍为 31 个尚未回收的临时标签，包括保留的大区域及别名；
真实容量耗尽仍显示 LABEL OVERFLOW 并清空该帧，不能宣称任意数量区域都支持。

tb_color_shape 新增：目标前 144 个分散单像素色点、多个合并小 U 区域的父标签复用、
长条有效区域贯穿碎点行。坐标/颜色/面积与独立 BFS 对照，全部通过；
原高密度棋盘格仍触发真实容量溢出，忙帧/重置/轮廓种子行为也通过。
另补测 12 个确定性随机碎点场景，包括碎点粘到目标边缘；BFS 对照均通过。
七项完整检测回归通过，包括 1731 个轮廓场景和完整 ISP。

掩码标题改为 MASK V4。check_synthesis.ps1 默认隔离目录改为 work_syn_v4，
-Implement 输出 work_syn_v4/shape_mask_v4.bit；前一 work_syn/shape_mask_v3.bit 保留。
V4 已完整实现和 bitgen：Setup WNS=+0.116 ns、Hold WNS=+0.020 ns，STNS/HTNS=0，
STA coverage=95.92%；最终 18883 slice（89.00%）、72 ERAM、26 DSP。
bit 大小 1789539 字节，SHA256=73341191C0E47501ED42316E90147D915161C98EEB456D282E8BE18A83AE1367。
脚本新鲜度、门级/最终时序与容量检查通过；尚未下载 FPGA、尚未上板复测。

## 2026-10-09 后续：方向/尺度容差与 MASK V3 诊断

用户确认加载了 18:46:02 生成的轮廓分类版 bit，但实物仍对平面内角度及大小敏感；
用户讨论 CNN 后明确继续传统算法。不能再把问题归因为没有删除旧填充率分类器或下载旧 bit。
主工程 *_Runs 的上述 bit 是用户生成的，本次使用独立 work_syn 构建，不覆盖用户产物。

轮廓简化距离由 L1 长度改为 max(|dx|,|dy|)+3*min(|dx|,|dy|)/8，
相对欧氏长度误差小于 7%，避免 L1 在轴向/对角方向有约 41% 差异。
容差改用链码周长推导的 Q4 尺度值，最低一掩码像素；
不再按水平外接框尺寸分档。仍保留闭合 DP、角点清理、凸性、角度、圆度与面积检查。
这些改动降低实现中的方向/尺度偏差，不代表真实颜色掩码缺损问题已解决。

新增 detection_mask_osd_rgb96.v（CompileOrder 69），叠加在 mode OSD 与 detection overlay 之间，
同步增加两拍 data/valid/SOF/tlast 延迟。右上角 x944..1263/y16..195 显示 CCL 实际接受的
320x180 红/绿/蓝/黑掩码，下面显示 MASK V3。独立三银行单读单写 RAM；
分别保护正在显示、等待帧提交和正在采集的图像，不给 CCL 主掩码增加读口。
掩码随稳定检测发布并在显示 SOF 提交，忙时跳帧；不是每帧实时缩略原图。
k4 控制框、掩码和诊断面板，原模式名称保留。

每目标诊断行在 x16..271/y176..239，V 为原始近似顶点数、E 为拒绝码。
类别仍经过三次稳定，V/E 属于本次原始分类，不应将两者短暂差异当作接线错误。
E=0 接受，1 碰边，2 跟踪失败/超时，3 点 RAM 容量，4 DP 堆栈，5 非凸，
6 面积/孔洞，7 顶点数复杂度，8 四边形角度，9 圆度。LABEL OVERFLOW 仍单独显示。
新固件必须显示 MASK V3；实物误判应拍摄整个画面含右上掩码和左侧 V/E，再决定颜色阈值/形态学调整。

最新轮廓测试为 1731 个几何公式场景（不是实拍），每 5 度、六种尺寸、亚像素位置与轻微倾斜，
矩形/圆形覆盖半圈，三角形覆盖完整 360 度；
另含完整大圆、环形和小孔矩形。新增掩码逐像素验证覆盖三个银行、帧内采集/发布、
等待提交时继续采集、字符、关闭、输入间隔与两拍控制；诊断文字和 ISP 元数据集成均有断言。
综合与实现结果以 verification/shape_detection/README.md 最新节为准；合成仿真不等于摄像头效果。

可复现：run_sim.ps1；check_synthesis.ps1 -Implement 会独立完成综合、布局布线和 bitgen，
生成 work_syn/shape_mask_v3.bit，检查新鲜报告、资源容量及最终 setup/hold。运行目录被忽略。
本次已完成完整实现和 bitgen：最终 Setup WNS=+0.112 ns、Hold WNS=+0.020 ns，
STNS/HTNS=0，STA coverage=95.87%；最终 18693 slice（88.11%）、72 ERAM、26 DSP。
bit SHA256=01A33E18C472F12A3941E700BA64F817B8F8CEE8C4AF78388113E4BB66ED6227。
检测七项/原模式五项回归通过，补充三角形完整旋转后 1731 场景通过。
未替用户下载 FPGA，未验证真实摄像头效果；需加载该独立 bit 并确认 MASK V3 后复测。

## 2026-10-09 更新：旋转/尺度稳定性修复与三角形

用户实板反馈：矩形稍转就成为 CIRCLE/UNKNOWN，完整可见的圆形靠近/旋转时失败，三角形不识别。
用户确认主要是平面内旋转，也有轻微倾斜；近距离圆形没有被画面裁剪。
旧版仅靠水平包围框填充率与宽高比，无法可靠区分旋转矩形与圆形；三角形尚未实现。
本节是最新状态，下面 10 月 8 日的分类规则和时序数据仅属旧版记录。

已新增 shape_contour_classifier.v（CompileOrder 67）：Moore 外轮廓跟踪、
2048×17bit 同步轮廓 RAM、闭合 Douglas–Peucker 多边形近似、有界 16 项堆栈、
随尺寸调整的距离容差、半像素量化容差、近共线/短假边清理、凸性及角度检查。
三顶点为 TRIANGLE（shape=3）；四顶点且角度约 53..127° 为 RECT；
5..12 顶点且链码圆度满足 P²≤16A 为 CIRCLE；其余 UNKNOWN。
链码正交/对角步长用 Q8 的 256/362；整数叉积/L1 容差，无除法/浮点/CNN。
外轮廓面积与 CCL 面积比拒绝大孔洞/环形，允许小内部缺色。
画面边界裁剪、跟踪超时、2047 边界点容量耗尽、堆栈溢出和非凸输出 UNKNOWN。
CCL 新保存各根的顶行种子 x；合并标签和前四排序时同步转移种子，仅对最大四区域分类。
Moore 核使用掩码读端口，轮廓结束前保持 mask RAM 不可写，视频继续正常流动。

已新增 detection_result_stabilizer.v（CompileOrder 68），按颜色/最近中心关联，
连续三次相反分类才改变旧类别；第一次出现直接显示，坐标和数量随最新检测更新。
目标消失/溢出立即清除，连续 UNKNOWN 三次会使旧类别失效，不无限保留旧结果。
这是类别稳定，不是完整运动跟踪；同色目标交叉可能关联错误，类别改变多等两次更新。
两个模块接入 isp_top；检测 overlay 显示 TRIANGLE，仍为三拍视频/控制延迟；原按键功能保留。
未改变 RGB 分割阈值，未实现形态学。实物光照、颜色分割破损仍需上板诊断。

开源传统方法参考增加 OpenCV 官方 Douglas–Peucker 文档；是整数 RTL 独立实现，未运行 OpenCV。
ModelSim 共十一项测试通过：原五项、检测六项，含 291 个旋转/尺度/轻微倾斜场景、
画面高度约 95% 的完整大圆、三角形文字、CCL 种子接入、同色排名交换、三次类别确认，
以及完整 720p 三颜色四目标 ISP 集成；ISP demosaic/AWB 仍使用仿真替身。
综合使用新的 verification/shape_detection/check_synthesis.ps1，生成被忽略的 work_syn 临时工程，
不覆盖主工程 *_Runs 或现有 bit；本版综合资源和时序以检测 README 最新节为准。
TD 6.2.168116 全工程门级综合通过：Setup WNS=+0.429 ns、Hold WNS=+0.114 ns，setup/hold 无违例。
资源 21037 LUT、17802 寄存器、16840 slice（79.37%）、51 ERAM、24 DSP，STA coverage=94.81%。
统一掩码单读口及轮廓点单写口以推断 ERAM，几何运算分级寄存，周长平方用 20 周期移位累加。
没有为新算法放宽 SDC，综合估计不等于最终布局布线时序。
尚未对本版完成布局布线、生成 bit 或重新上板；已有 bit 不能代表本次修复。

## 2026-10-08 更新：纯 FPGA 颜色块与简单形状检测

已实现用户确认的传统算法方案，纯 RTL，无 CNN/CPU/OpenCV 运行依赖。
新增 isp/color_reduce_rgb96.v、color_shape_detect.v、detection_overlay_rgb96.v，
已接入 isp_top、design_top_wrapper 及 TD .al（编译顺序 64/65/66）。
AWB RGB888 四像素输入 → 4×4 均值降采样 320×180 → RGB 主通道阈值 →
同色四连通域 union/find → 面积过滤 → 填充率/宽高比分类 → 四个最大目标 → 框/类别/数量叠加。
RGB 默认阈值为主通道 >=80，且比其余两通道各高 >=32；颜色可通过模块参数调整。
32 项标签表中最多分配 31 个临时标签；容量耗尽清空本次结果并显示 LABEL OVERFLOW。
最多显示四个区域，N/R/G/B 是显示目标计数；不是超过四个目标时的全场总数。
RECT 填充率 >=88%；CIRCLE 填充率 68%..86% 且宽高比 0.85..1.18；其他 UNKNOWN。
形状判据用于完整可见、背景分离的色块，不能当作通用轮廓分类；未实现周长/圆度或形态学。
单份掩码 RAM 在采集/分析间切换，忙时跳过新的检测帧，视频流不断；移动目标的框会滞后。
检测始终读取 AWB 原彩色，与四种显示模式独立。原模式名称 OSD 保留。
检测叠加新增三拍同步 data/valid/SOF/tlast 流水；结果和使能在帧起始锁存。
k4=I_button[3]/C7，低有效、消抖、长按一次，切换检测叠加，默认开启；下一显示帧生效。
k1/k2/k3/sw1 原功能保留。关闭叠加不会停止检测。

开源参考：实际阅读 Topi-ab/linkruncca 的原始 RTL，参考 MIT ObNoDog 2024 的
掩码缓存/CCL/区域筛选/叠加架构；本工程按四像素接口独立适配，未直接接入原开源核。
LinkRunCCA 可选原核诊断在本机 ModelSim 存在 X 传播，未通过；不能声称与原核交叉验证通过。
本工程使用独立 BFS 验证 CCL，详细来源、许可、算法限制及命令见 verification/shape_detection/README.md。
ModelSim 新增四项测试及原五项回归全部通过，含完整 720p 合成帧、逐像素 OSD、真实 k4 消抖。
ISP 集成测试用 demosaic/AWB 替身，不等于摄像头/DDR/HDMI 实板验证。
TD 6.2.168116 全工程门级综合通过：Setup WNS=+0.354 ns、Hold WNS=+0.114 ns，setup/hold 无违例。
门级资源 20475 LUT、17406 寄存器、16416 slice（77.38%）、48 ERAM、17 DSP；STA coverage=94.99%。
详细结果见检测 README；尚未对本版完成布局布线、生成 bit 或上板验证。
现有 td_project/*_Runs 下 bit 与运行产物是此前已有的本地改动，不属于本次检测实现。


## 2026-10-06 后续更新：模式名称 OSD

用户要求先参考 lab_ex3_osd_SC500_720P 工程，实现屏幕左上角显示当前算法名称。
已复制参考工程 osd_char_lib.v 字库到本工程 isp 目录，参考目录未修改。
新增 mode_osd_rgb96.v：四像素 RGB888 处理，x=16..239、y=16..47 黑底黄字，
显示 NORMAL / BINARY / SOBEL / CARTOON。在 isp_top 四模式选择后、96→128 打包前叠加，
使用 video_mode_d2，增加一拍 data/valid/SOF/tlast 同步延迟，名称随图像存入 DDR。
两个模块已加入 .al 工程清单（CompileOrder=62/63）。

ModelSim 原四项回归及新增 tb_mode_osd.sv 均通过；tb_isp_modes 增加 OSD 集成检查，
包括模式对齐及穿过整个面板的全宽正常帧。模块继续沿用原链路的实时视频约定，
不提供独立 AXI 停顿缓存。TD 6.2.168116 已完成 OSD 版本全工程展开、RTL/门级综合，
门级估计 Setup WNS=+0.684 ns、Hold WNS=+0.114 ns，违例数均为 0；原工程警告仍存在。
同口径门级报告相比上一版增加 193 LUT、121 寄存器、180 slice，ERAM 39、DSP 8 不变。
临时 osd_check.prj/tcl/area 位于 verification/edge_modes，被忽略，不应依赖新克隆存在。
本次尚未完成 OSD 版本布局布线、生成 bit 或上板验证。

用户此前已选择颜色块/简单几何形状检测，在 HDMI 叠加框、类别和数量，
但目前只制定了检测方案，尚未实现目标检测 RTL。最新实际执行任务是模式名称 OSD。
此前文档中的综合与布线状态记录属于当时版本，不能直接用于本次 OSD 源码。

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
