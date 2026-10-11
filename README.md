# SC520 摄像头至 HDMI：图像处理、形状检测与延迟可视化

更新：2026-10-11。Anlogic PH1P35MDG324，TD 6.2.168116，工程入口为 `td_project/camera_to_dsi_display.al`，顶层为 `design_top_wrapper`。

当前摄像头初始化使用 SC520CS 1280×720@60 配置；备用2560×1920@30寄存器表未启用。显示链路采用四像素RGB888接口、四槽DDR缓存和HDMI输出。

## 功能与操作

| 输入 | 功能 |
|---|---|
| k1，D5 | 正常 → 二值化 → Sobel → 卡通 → 灰度 |
| k2，A9 | 降低摄像头增益，按住连续调整 |
| k3，B9 | 提高摄像头增益，按住连续调整 |
| k4，C7 | 开关检测框、计数、MASK和V/E诊断，默认开启 |
| sw1，A4 | 保留输入，当前无功能 |

按键低有效；k1/k4消抖并在帧边界生效。k2/k3不受模式或sw1限制，只调摄像头增益，不调曝光或算法阈值。二值化阈值固定64，Sobel/卡通轮廓阈值固定60。

- 红绿检测：4×4均值降采样至320×180，四连通域、最大四区域、轮廓分类及类别稳定；识别RECT/CIRCLE/TRIANGLE/UNKNOWN，蓝色主导区域作为背景。
- 显示：固定RGB增益、饱和度、模式名称、透明三色Logo；检测输入取自AWB输出，独立于后续显示处理。
- 延迟面板：左下角CAP/DISP来源帧号、AGE帧龄和LAT毫秒延迟；数值为十进制，异常显示WAIT及十六进制原因码。

LAT测量CSI-2帧开始事件至同帧首个有效像素到达HDMI编码前接口的时间，不包含传感器曝光、内部处理、TMDS编码和显示器响应。AGE是来源帧号差，不能直接当作毫秒值；60 fps下AGE=2对应约33.3～50 ms的帧龄区间。

## 当前实现与验证

用户2026-10-11 12:38 TD最终布局布线报告：

| 资源/时序 | 结果 |
|---|---:|
| Slice | 19163/21216，90.32% |
| LUT6 | 17827/21216，84.03% |
| 寄存器 | 20269/42432，47.77% |
| ERAM | 73/108，67.59% |
| DSP | 26/40，65.00% |
| Setup / Hold 最差裕量 | +0.155 ns / +0.020 ns |

Logo由RGB888加透明标记改为三色加透明的2位索引，ROM从384000 bit降至30720 bit；TD确认Logo占用从20块ERAM降至2块。尺寸160×96、位置和透明轮廓不变，边缘过渡色归并到三种主色。

| 验证 | 状态与范围 |
|---|---|
| 延迟ModelSim | 四组PASS：单元、四时钟域集成、CSI晚启动、720p完整写入边界；厂商FIFO存储使用替身 |
| Logo ModelSim | PASS：全部15360像素、透明轮廓、四像素顺序、两帧720p、控制信号与复位 |
| 当前全链路回归 | 未完整重跑；历史1731个轮廓场景不等于当前实板准确率 |
| 实板 | 用户反馈画面正常、AGE=2、LAT约30～40 ms；实际帧率和端到端延迟未做外部标定 |

当前仍须核对CDC同步器及负载路径。此前两条按映射引脚名添加的false-path在TD中未匹配，已移除无效命令；最新正时序裕量不是这些例外产生的效果，清理后尚未再次Run。

## 文档与复现

- [AI交接](AI_HANDOFF.md)：工程约定、当前状态及下一步。
- [显示与按键](verification/edge_modes/README.md)
- [红绿及形状检测](verification/shape_detection/README.md)
- [延迟测量与WAIT诊断](verification/video_latency/README.md)
- [三色Logo生成与验证](verification/logo/README.md)
- [资源对比](verification/resources/README.md)

在工程根目录执行，默认ModelSim路径为 `C:\altera\14.1\modelsim_ase\win32aloem`，脚本可用 `-ModelSimBin` 指定：

```powershell
powershell -ExecutionPolicy Bypass -File verification/video_latency/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/logo/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/shape_detection/run_sim.ps1
```

TD综合、布局布线、bit生成和下载由用户操作。发布内容包含源码、工程配置、验证脚本及文档；本次不更新仓库内历史TD生成文件。克隆后应重新Run，不能把旧bit或旧报告当作当前源码的结果。
