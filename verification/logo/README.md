# 三色 Logo ROM

原图 `user_source/hdl_source/anlogic_logo_rom.v` 保留，取160像素宽的第32..127行，显示尺寸160×96、位置x=1104..1263/y=608..703不变。

`generate_rom.ps1` 将原图不透明像素按RGB平方距离归并到红色 `ED1C24`、深蓝 `1C2D4E`、白色 `FFFFFF`；透明像素仍透明。原图有579种不透明颜色，三色化舍弃边缘过渡色，因此不是无损压缩。

`anlogic_logo_words.v` 每组四像素存8位索引：00透明、01红、10深蓝、11白。同步读取索引后组合解码回原100位接口，Logo叠加模块不变、整体仍为两拍。存储从3840×100=384000 bit降到3840×8=30720 bit，减少92%。

用户2026-10-11 12:38 TD报告确认ROM为2块ERAM（压缩前20块），整个Logo叠加模块为115个逻辑LUT、209个寄存器、2块ERAM、0 DSP。整机ERAM从91降到73；Slice变化包含重新布局/打包的影响，不能用位数比值推定。完整对比见 [资源 README](../resources/README.md)。

透明/红/深蓝/白像素分别为8973/2462/3617/308。预览：[原图](original.png)、[三色图](three_color.png)。

```powershell
powershell -ExecutionPolicy Bypass -File verification/logo/generate_rom.ps1
powershell -ExecutionPolicy Bypass -File verification/logo/run_sim.ps1
```

测试从原始RGB ROM独立计算参考，逐一核对15360个像素，验证透明轮廓、四像素顺序、两帧720p叠加、有效信号/SOF/last两拍对齐、帧间空拍及复位。此测试不代替完整ISP或TD实现验证。

2026-10-11 ModelSim测试PASS（462244个视频测试周期）；编译0错误0警告，仿真0错误，仅原始ROM参考导致Starter建议容量提示。未自动运行TD、生成bit或下载。
