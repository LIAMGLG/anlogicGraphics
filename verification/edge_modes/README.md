# 图像显示与模式轮换

更新：2026-10-10。当前为五种显示模式；目标检测说明见 [检测 README](../shape_detection/README.md)。

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
  字库使用紧凑位图，C/T/N/4统一为8行高、最多6列宽。
- 安路Logo：右下角x=1104..1263、y=608..703，160×96，透明像素保留视频。
  图案来自 `user_source/hdl_source/anlogic_logo_rom.v`，原文件不变。
  `anlogic_logo_words.v`打包四个含不透明标志的像素，`logo_osd_rgb96.v`负责叠加。
- k4只切换检测叠加；模式名称和Logo始终显示。
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

**当前五模式、字库和透明Logo版本尚未完成仿真及TD实现。**历史测试结果不能直接用于当前源码，现有测试也不等于完整Logo验证。真实摄像头、AWB算术、DDR和HDMI不由上述替身测试覆盖。
TD Run由用户完成；重新加载 `td_project/camera_to_dsi_display.al`，检查Logo ROM推断、资源容量与最终时序后生成bit。
