# SC520实时图像处理、目标跟踪与红色矩形云台瞄准

更新：2026-10-20。基于安路PH1P35MDG324，在FPGA端完成摄像头采集、图像处理、颜色形状识别、轻量跟踪、运动检测、双轴云台瞄准和HDMI显示。

## 工程入口

- TD工程：`td_project/camera_to_dsi_display.al`；顶层：`design_top_wrapper`。
- 开发工具：TD 6.2.168116；器件speed 3。
- 摄像头：SC520CS，当前启用1280×720@60配置；备用2560×1920@30表未接入。
- 视频接口：四像素RGB888，四槽DDR缓存，HDMI输出。配置帧率不等于已经实测的视频或检测更新率。

## 功能与操作

| 输入 | 功能 |
|---|---|
| k1，D5 | NORMAL → BINARY → SOBEL → CARTOON → GRAY → MOTION → NORMAL |
| k2，A9 | 降低摄像头增益，按住连续调整 |
| k3，B9 | 提高摄像头增益，按住连续调整 |
| k4，C7 | 开关检测叠加；MOTION下控制运动框和状态 |
| sw1，A4 | 上电后先关闭，再打开启用红色矩形瞄准；关闭保持云台位置 |

按键低有效；k1/k4消抖且长按一次，模式在帧起始提交，叠加使能在显示SOF锁存。k2/k3只调摄像头增益，不调曝光或算法阈值。二值化阈值64，Sobel/卡通轮廓阈值60。

- **颜色形状检测**：AWB输出经4×4均值降采样至320×180，红绿分割、四连通域、最大四区域和轮廓分类，输出RECT/CIRCLE/TRIANGLE/UNKNOWN。蓝色主导区域作为背景。
- **轻量跟踪与坐标**：同色最近距离关联、固定槽编号1～4；类别改变连续三次确认，漏检保持两次、第三次清除，12次AWB SOF超时。暂失显示灰色虚线框与WAIT，不计入N/R/G。左侧显示包围框中心，例如 `1 X:0320 Y:0220`，单位为原图像素；暂失保持最后坐标，清除后撤行。
- **运动模式**：160×90灰度帧差，16×9个80×80原图区域，黄色框及WAIT/MOVE/STILL。首帧建立参考，连续两帧确认、保持3帧。区域数不等于物体数；该模式隐藏红绿框、坐标和MASK，红绿检测仍在后台运行。
- **显示处理**：RGB增益、饱和度、模式标题、MASK预览和160×96透明三色安路Logo。检测取自AWB输出，独立于后续显示处理。
- **延迟面板**：CAP/DISP来源帧号、AGE帧龄、LAT毫秒延迟，数值为十进制；异常显示WAIT及十六进制原因码。

LAT测量CSI-2帧开始至同帧首个有效像素到达HDMI编码前接口的时间，不含传感器曝光、内部处理、TMDS编码和显示器响应，也不代表检测结果响应时间。AGE是来源帧号差，不能直接换算为毫秒。

## 红色矩形自动瞄准

摄像头安装在双轴云台上，复用红色RECT跟踪结果，使其中心接近画面中心(640,360)。水平PWM：V1/J1第2脚；俯仰PWM：U1/J1第4脚。每次上电/复位后需先将SW1关闭一次，再打开才启用；建议画面正常后再打开。K4仅控制显示叠加。启动先保持中位约3秒；2026-10-20改为带来源帧号的图像误差变化率阻尼控制：按误差大小调速、按检测间隔与帧龄提前减速，保留死区、行程限幅和丢失/超时停止，不再逐步固定等待。当前采用用户确认的俯仰反向配置，名义行程为左右各45°、抬头60°、低头15°；SPEED_BOOST=1将基础速度指令放大约1.5倍，最大375 ticks/20 ms（7.5 us），实际响应仍需实板标定。舵机外部5 V供电并与FPGA共地。

接线、限位参数、仿真与上板步骤见[云台说明](verification/gimbal/README.md)。TD源文件列表与引脚已接入。最新本地Run报告见下表；最终行程、响应及长期稳定性仍需实板验收。

## 实现与验证状态

2026-10-13新增MOTION、四目标跟踪及中心坐标，已经接入ISP与TD源清单。坐标替换原V/E面板，八值共用串行BCD转换器，SOF后104拍统一提交；跟踪和运动叠加未增加主视频流水线延迟或新时钟域。

本地最新布线资源报告生成于2026-10-20 19:19:31，时序报告为19:19:28，综合层次包含red_rect_gimbal及gimbal_pd_rate：

| 资源/时序 | 结果 |
|---|---:|
| Slice | 20315/21216，95.75% |
| LUT6 | 19093/21216，89.99% |
| 寄存器 | 22321/42432，52.60% |
| ERAM | 83/108，76.85% |
| DSP | 26/40，65.00% |
| Setup / Hold最差裕量 | +0.119 ns / +0.020 ns |
| STA coverage | 95.19% |

数据来自本地 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_phy.area` 与 `final_timing.rpt`。云台层次为490逻辑LUT、236 ripple、346寄存器、0 ERAM、0 DSP，包含其中PD单元291/122/217，不能将父子层次重复相加。报告只证明该次构建，尚未建立源码/bit哈希对应记录及新增功能实板验收；仓库内历史生成文件不随本次提交更新。

Slice余量为901个。最终占用包括13660个普通LUT逻辑Slice、4441个加法器Slice、1222个仅寄存器Slice及992个分布式RAM/移位存储Slice，不能由LUT或寄存器利用率单独判断余量。正时序裕量不代替CDC检查、未覆盖路径核查或实板验证。

| 验证 | 已有记录与覆盖范围 |
|---|---|
| 颜色/形状 | CCL独立BFS、1731个合成轮廓场景、MASK及逐像素叠加回归PASS |
| 跟踪/坐标 | 固定ID、排序变化、漏检恢复、超时、坐标全范围、六帧叠加及四次720p检测ISP仿真PASS |
| 运动/六模式 | 均值和门限、四帧720p运动、逐像素框、八帧720p运动ISP、标题及按键回归PASS |
| 延迟/Logo/字库 | 四组延迟、全部15360个Logo像素、两帧720p及字库回归PASS |
| 云台控制 | 813组PD数值对照、启动/跨域/PWM/限幅、1.5倍速度和两个延迟闭环模型PASS；PD版四帧720p帧号关联/暂失恢复PASS |
| 实板 | 用户反馈先关闭SW1上电、画面正常后开启可瞄准；最新60°行程、加速与阻尼参数的最终效果仍待验收 |

视频基础项为2026-10-13已有验证记录；云台与检测回归于2026-10-20执行，行程/加速修订后重跑云台相关测试，未重复完整720p链路。上述TD报告来自用户本地Run，本文整理未重新运行TD。ISP测试中的demosaic/AWB及部分FIFO存储为替身，不覆盖真实摄像头、AWB算术、DDR/HDMI硬件。合成轮廓测试数量不等于实拍准确率。

## 已知限制

- 检测忙时跳帧，检测更新率与视频帧率不同；同色粘连、交叉、遮挡和大位移可能误检或交换ID。四槽包含暂失目标，槽满时等待释放。
- 红绿分割受光照、AWB和反射影响；31个有效标签槽，最小面积25、宽高各5，标签溢出清空该次检测结果。
- 坐标为降采样包围框中心，不是质心或单像素测量精度；卡通图像相对原图下移一行、右移两像素，框可能偏移。
- 帧差没有全局亮度、增益变化或摄像头晃动补偿，小而慢的运动可能被过滤。
- SW1开启上电曾出现黑屏WAIT 1221；用户确认先关闭SW1上电、画面正常后开启可正常工作，已保留上电许可保护，底层根因尚未确定。现有高占用、时钟布线及未驱动信号告警需结合具体路径核查。
- 延迟邮箱曾出现CDC Hold违例；两条第一级入口例外已保留，修改时必须检查对象匹配及第二级路径，详见[CDC检查](verification/cdc_constraints/README.md)。

## 文档与复现

- [云台接线、控制、行程与验证](verification/gimbal/README.md)
- [AI交接](AI_HANDOFF.md)：工作约定、CDC提醒、核心文件及后续优先级。
- [显示与按键](verification/edge_modes/README.md)
- [颜色形状检测](verification/shape_detection/README.md)与[跟踪、中心坐标](verification/shape_detection/TRACKING.md)
- [独立运动检测](verification/motion_detection/README.md)
- [延迟测量与WAIT诊断](verification/video_latency/README.md)
- [三色Logo](verification/logo/README.md)、[历史资源对比](verification/resources/README.md)

在工程根目录执行；默认ModelSim路径为 `C:\altera\14.1\modelsim_ase\win32aloem`，可用 `-ModelSimBin D:\modelsim10.4\win64` 指定其他安装：

```powershell
powershell -ExecutionPolicy Bypass -File verification/gimbal/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/video_latency/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/logo/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/resources/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/shape_detection/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/motion_detection/run_sim.ps1
```

TD综合、布局布线、bit生成和下载由用户操作。发布包含源码、工程配置、验证和文档，排除本地日志、仿真工作目录及TD生成产物。克隆后检查工程路径并重新Run，用当前构建报告与bit进行验收。
