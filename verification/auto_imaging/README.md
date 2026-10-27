# 自动曝光与白平衡合入

2026-10-27：按用户要求从 `user_source/new/hdl_source` 选择性合入 AE/AWB，保留当前卡通、云台和 SW1 运动抑制。TD 使用主目录源码，不编译 `new` 参考目录。

- 顶层默认 `AUTO_AE=1, AUTO_AWB=1, NATURAL_COLOR=1, SHOW_EXPOSURE=1, AE_TARGET=135`。
- K1 仍为 NORMAL/BINARY/SOBEL/CARTOON/GRAY/MOTION；K2/K3 改为降低/提高 AE 目标亮度，每次 5，范围 95～215，长按连续调整。设置 `AUTO_AE=0` 时恢复手动增益。
- AE 从 AWB 输出统计中心 ROI 亮度及高光比例，经 9 位握手邮箱进入 24 MHz 域。预热 8 个有效统计帧，每次写入后等待 4 个有效统计帧；过亮先降增益再减曝光，过暗先增曝光再增增益；I2C 错误或超时锁定故障，复位后重试。
- AWB 从未校正 RGB 的中心 ROI 中选择亮度适中、颜色差异有限的样本，估计 G/R、G/B。复用两个现有除法器，增益限于 0.5～2，按 1/8 平滑，仅在下一输入 SOF 更新。样本不足时保持增益。
- `NATURAL_COLOR=1` 取消原固定 RGB 偏色增益和 1.25 倍饱和度增强，保留原流水线拍数；设置为 0 可恢复原显示增强。卡通模块、Sobel 和 CARTOON 标题保持原实现。
- AE 参数写入事件或明显 AWB 调整后，运动检测暂停 4 次视频 SOF，之后由原运动模块重建参考帧；原 SW1 启用期间抑制及关闭后 12 次 SOF 等待仍保留。
- 顶部增加 `AE xx.xMS Gxx.xxX`，表示已完成 I2C 写入的设定值，非传感器读回。初始化显示 WAIT，故障显示 ERR。曝光换算沿用同事的 720p60/VTS1000 标定假设。

```powershell
powershell -ExecutionPolicy Bypass -File verification/auto_imaging/run_sim.ps1
powershell -ExecutionPolicy Bypass -File verification/edge_modes/run_sim.ps1
```

2026-10-27 本地 ModelSim ALTERA 10.3c 验证全部 PASS：自动成像四组测试、AE/AWB 四次 SOF 运动抑制集成测试，以及 `edge_modes/run_sim.ps1` 原有卡通、Sobel、六模式、12 帧 720p 运动/SW1 联动、标题 OSD 和增益回归。小数点修复后重新通过曝光 OSD 与六模式标题 OSD 测试。

新增仿真覆盖不完整帧丢弃、ROI 亮度/通道和、AWB 校正方向及帧边界更新、异步邮箱数据、AE 预热/等待/明暗调节/按键/错误停写、曝光显示数值以及自然色彩流水线。曝光 OSD 按像素验证数字、小数点和帧内数值锁存；原字库不含小数点，已在曝光面板内补画。AWB 仿真使用真实统计、校正和 `signal_delay` RTL，厂商 RAM/除法 IP 使用行为模型；既有 ISP 回归中的 demosaic/AWB 仍为替身。

未运行 TD 综合、布局布线或 bit 生成，未覆盖已有 Run。现有 SDC 的两个延迟邮箱入口例外和层级保持原样；新增 AE 邮箱跨 MIPI/24 MHz 原有异步时钟组，同步器第二级仍应在新 Run 检查，负载在应答前保持稳定。旧报告不能证明新增逻辑的资源或时序，实板还需验证亮暗变化、白平衡收敛和颜色检测效果。
