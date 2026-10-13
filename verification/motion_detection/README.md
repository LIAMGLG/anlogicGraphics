# 独立运动检测模式

2026-10-13新增RTL；ModelSim验证见下，尚未运行TD或生成/下载新bit。

## 操作与显示

- k1循环：NORMAL → BINARY → SOBEL → CARTOON → GRAY → MOTION → NORMAL，在帧起始切换。
- MOTION保留彩色图像、模式标题、Logo和已有延迟面板，隐藏红绿框、分类列表及MASK预览。
- 黄色两像素边框表示活跃的80×80运动区域，同一物体可以激活多个区域，区域数不能当物体数。
- 状态文字位于x=16..143/y=64..79：WAIT为等待参考帧，STILL为无活跃区域，MOVE为有活跃区域。该版不显示变化百分比或目标ID。
- k4控制区域框及状态文字。关闭显示时检测继续；k2/k3仍只调摄像头增益。

## 算法与流水线

从未加显示增益的AWB RGB取数，延迟四拍与现有gain两拍、edge两拍的控制对齐；没有修改AWB提前SOF约定。
每像素Y=(R+2G+B)/4截断，再对8×8像素求均值，生成160×90、8位灰度流。
同步RAM读取上一帧同地址值，在下一周期写入当前值，样本至少相隔两拍，不依赖同地址同拍RAM读写行为。
绝对差严格大于16时计为变化像素。每10×10灰度区域累计至少8个变化像素后激活，计数饱和于门限。
连续两帧激活才显示；确认后保持3个后续帧，若不再确认则撤框。首帧只建立参考，退出模式清空有效状态，重入重新建立参考。
未完成帧导致下一帧参考失效，完成一帧后恢复比较。输入应符合原实时视频链路的完整行宽和行结束约定。

帧结束发布144位区域图；显示侧SOF锁存，使用上一来源帧的结果。运动叠加三拍，与原检测叠加并行，按对齐后的模式选择进入Logo，不增加主视频链路延迟。
红绿检测仍在后台运行，只在MOTION隐藏叠加；该版不复用或删除原有CCL，不增加新时钟域和跨域控制。

支持的尺寸为80的整数倍，最大1280×720，区域图固定16列×9行；工程使用1280×720，小型单元测试使用80×80。

## 资源与限制

- 前帧灰度：14400×8=115200 bit；按2K×8配置约8块ERAM。
- 纵向累加：160×14=2240 bit；目标提取同步RAM，实际映射待TD确认。
- 区域图、历史、保持计数以及16个区域列计数使用寄存器，所有运算为加减/移位/比较，未引入乘除法或DDR访问。
- 尚无新增LUT/Slice/ERAM实测结果；不能用历史布局报告证明新RTL资源或时序通过。
- 帧差受光照、AWB、增益变化和摄像头晃动影响；该版没有全局亮度补偿或手动增益切换抑制。建议固定摄像头，调好增益后演示，必要时退出再进入MOTION重建参考。
- 运动区域提示不是完整轮廓、目标追踪或越线计数；很小或很慢的运动可能被均值与门限过滤。

SDC及原有req1/ack1同步器未修改，两个已验证第一级入口例外保留。新增电路仅在ISP时钟域运行；最终Setup/Hold和RAM提取须由用户TD Run确认。

## 复现验证

```powershell
powershell -ExecutionPolicy Bypass -File verification/motion_detection/run_sim.ps1 -ModelSimBin D:\modelsim10.4\win64
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1 -ModelSimBin D:\modelsim10.4\win64
powershell -ExecutionPolicy Bypass -File verification/shape_detection/run_sim.ps1 -ModelSimBin D:\modelsim10.4\win64
```

| 测试 | 覆盖 |
|---|---|
| tb_motion | 独立逐像素RGB/8×8均值参考、valid间隔、提前SOF、首帧、差值等于门限、稳定/保持、不完整帧、退出重入、复位 |
| tb_motion_720p | 四个连续完整720p帧、两处运动、最后像素和第143区域、无帧间空白 |
| tb_motion_overlay | 独立逐像素区域边框参考、四通道顺序、帧内结果锁存、关闭显示、模式旁路、三拍控制 |
| tb_motion_isp（edge_modes脚本） | 八帧720p实际ISP显示链路，AWB数据对齐、隐藏红绿叠加、黄色框、退出重入及连续SOF；仅demosaic/AWB为替身 |

现有六模式、标题、RGB增益/饱和度、红绿CCL/轮廓/稳定器/MASK/叠加及720p红绿ISP回归配合运行。仿真不覆盖真实摄像头、实际AWB运算、DDR和HDMI硬件。
