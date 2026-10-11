# 图像显示与模式轮换

更新：2026-10-11。当前为五种显示模式；目标检测说明见 [检测 README](../shape_detection/README.md)，新增采集到HDMI延迟可视化见 [延迟 README](../video_latency/README.md)。

## 模式与操作

k1循环：**NORMAL → BINARY → SOBEL → CARTOON → GRAY → NORMAL**，上电默认NORMAL。
模式在帧起始生效，左上角黑底黄字同步显示名称。

| 模式 | 功能 |
|---|---|
| NORMAL，0 | 显示经AWB和固定RGB增益处理的彩色图像 |
| BINARY，1 | 亮度与阈值比较，输出黑白 |
| SOBEL，2 | Sobel边缘提取，采用两像素采样 |
| CARTOON，3 | 每通道量化到0/85/170/255，叠加Sobel黑轮廓 |
| GRAY，4 | Y=floor((R+2G+B)/4)，三通道均输出Y |

k2降低摄像头增益，k3提高摄像头增益，低有效、按住连续调整；不受显示模式或sw1限制。
sw1保留输入，当前无功能。k1/k4消抖且长按只触发一次。

**算法阈值按键功能已删除。**二值化阈值固定64，Sobel阈值固定60，后者同时用于卡通轮廓。
如需改变算法阈值，修改isp_top中的常量参数并重新生成bit。

## 显示处理与叠加

- AWB后固定增益：R×147/128、G×122/128、B×109/128，向下取整、超出255饱和。
- 模式选择后饱和度1.25：近似Y=(R+2G+B)/4，按Y+1.25×(C−Y)调整并限制到0～255。
  灰度及黑白图像保持不变，文字/框/Logo在它之后叠加。
- 模式名称：x=16..239、y=16..47，16×16字库放大两倍。
  字库使用紧凑位图，C/T/N与其他字母统一为8行高、最多6列宽；数字4已与其他数字统一为12行高度和底线。
- 安路Logo：右下角x=1104..1263、y=608..703，160×96，透明像素保留视频。
  图案来自 `user_source/hdl_source/anlogic_logo_rom.v`，原文件不变。
  `anlogic_logo_words.v`每组四像素存8位索引，00透明/01红/10深蓝/11白，同步读取后组合解码回原100位像素接口；`logo_osd_rgb96.v`负责叠加，两拍延迟不变。原图过渡色归并到三种主色，透明轮廓保持。存储量减少92%，用户TD报告确认20→2块ERAM。生成及验证见 [Logo README](../logo/README.md)。
- k4只切换检测叠加；模式名称和Logo始终显示。
- DDR读取和hdmi_mixer后新增始终开启的左下角CAP/DISP/AGE/LAT面板，x=16..367、y=608..671；无效测量显示WAIT。该输出级增加一拍并同步延迟RGB/DE/HS/VS，不改变ISP内各级延迟。
- 检测读取AWB原RGB，独立于显示模式、增益和饱和度。

显示主连接在 `user_source/hdl_source/isp/isp_top.v`，算法、OSD和Logo均为独立模块，已加入TD工程清单。

## 时序与限制

RGB增益两拍；Sobel及对齐路径两拍；灰度组合转换不另加拍；饱和度两拍；模式名称一拍；MASK两拍；检测叠加三拍；Logo两拍。后续再进入128位打包。
模式通道为3位，各级必须保持数据、valid、SOF、last与模式对齐。

卡通按相邻两像素平均后量化，复用Sobel窗口中心；相对原图下移一行、右移两像素，首行和行首为黑色，边界内容不能完整保留。它不是双边滤波卡通算法。
Sobel保留首两行和行首遮罩。二值化模块的分量截断亮度近似最大253，灰度模式的完整求和结果最大255。
模块沿用实时视频链路约定，没有完整独立背压缓存。

## 验证

在工程根目录手动执行：

```powershell
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
```

支持 `-ModelSimBin`，默认 `C:\altera\14.1\modelsim_ase\win32aloem`；脚本检查退出码和PASS标记。

| 测试 | 覆盖内容 |
|---|---|
| tb_edge_modes | Sobel参考、边界/间隔/复位、按键消抖和五模式轮换 |
| tb_cartoon | 量化、黑轮廓、窗口空间对齐 |
| tb_isp_modes | 增益、五路选择、连续帧及模式名称集成；使用demosaic/AWB替身 |
| tb_mode_osd | 五种名称、字库像素、坐标和控制延迟 |
| tb_rgb_gain | 全256输入值、四像素位置、饱和与复位 |

用户2026-10-11 12:38完成当前三色Logo版本TD实现：Slice 90.32%、ERAM 73/108、DSP 26/40，Setup +0.155 ns、Hold +0.020 ns；详见 [资源 README](../resources/README.md)。

**当前完整五模式链路尚未重跑全套回归。**三色Logo独立ModelSim测试已通过15360像素、透明轮廓、四像素顺序、两帧720p、控制对齐及复位；数字4的高度/底线由延迟单元测试覆盖。历史结果不能直接作为当前全链路验证，真实摄像头、AWB算术、DDR和HDMI不由上述替身测试覆盖。

用户反馈画面连续更新；五模式及三色Logo的逐项实板确认仍待完成。后续TD Run和下载由用户操作；CDC约束待核对事项见 [延迟 README](../video_latency/README.md)。
