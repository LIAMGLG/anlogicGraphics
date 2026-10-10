param([string]$ModelSimBin = 'C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $library = 'verification/edge_modes/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $library
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv `
        user_source/hdl_source/isp/color_gain_rgb96.v `
        user_source/hdl_source/isp/saturation_rgb96.v `
        user_source/hdl_source/isp/grayscale_rgb96.v `
        user_source/hdl_source/isp/anlogic_logo_words.v `
        user_source/hdl_source/isp/logo_osd_rgb96.v `
        user_source/hdl_source/isp/color_reduce_rgb96.v `
        user_source/hdl_source/isp/color_shape_detect.v `
        user_source/hdl_source/isp/shape_contour_classifier.v `
        user_source/hdl_source/isp/detection_result_stabilizer.v `
        user_source/hdl_source/isp/detection_overlay_rgb96.v `
        user_source/hdl_source/isp/detection_mask_osd_rgb96.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        user_source/hdl_source/isp/mode_osd_rgb96.v `
        user_source/hdl_source/isp/cartoon_96.v `
        user_source/hdl_source/isp/edge_detect_96.v `
        user_source/hdl_source/key_video_mode.v `
        user_source/hdl_source/key_remove_shakes.v `
        user_source/hdl_source/isp/binary_threshold_96.v `
        user_source/hdl_source/isp/isp_top.v `
        verification/edge_modes/tb_edge_modes.sv `
        verification/edge_modes/tb_rgb_gain.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $library tb_edge_modes `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/edge_modes/simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'vsim failed' }
    if (!(Select-String -Quiet -LiteralPath verification/edge_modes/simulation.log -Pattern 'PASS: Sobel reference')) {
        throw 'Simulation did not reach PASS'
    }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv verification/edge_modes/tb_cartoon.sv
    if ($LASTEXITCODE -ne 0) { throw 'Cartoon vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $library tb_cartoon `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/edge_modes/cartoon_simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'Cartoon vsim failed' }
    if (!(Select-String -Quiet -LiteralPath verification/edge_modes/cartoon_simulation.log -Pattern 'PASS: cartoon color quantization')) {
        throw 'Cartoon simulation did not reach PASS'
    }
    $ispLibrary = 'verification/edge_modes/work_isp'
    & (Join-Path $ModelSimBin 'vlib.exe') $ispLibrary
    if ($LASTEXITCODE -ne 0) { throw 'ISP vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $ispLibrary -sv `
        user_source/hdl_source/isp/color_gain_rgb96.v `
        user_source/hdl_source/isp/saturation_rgb96.v `
        user_source/hdl_source/isp/grayscale_rgb96.v `
        user_source/hdl_source/isp/anlogic_logo_words.v `
        user_source/hdl_source/isp/logo_osd_rgb96.v `
        user_source/hdl_source/isp/color_reduce_rgb96.v `
        user_source/hdl_source/isp/color_shape_detect.v `
        user_source/hdl_source/isp/shape_contour_classifier.v `
        user_source/hdl_source/isp/detection_result_stabilizer.v `
        user_source/hdl_source/isp/detection_overlay_rgb96.v `
        user_source/hdl_source/isp/detection_mask_osd_rgb96.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        user_source/hdl_source/isp/mode_osd_rgb96.v `
        user_source/hdl_source/isp/cartoon_96.v `
        user_source/hdl_source/isp/edge_detect_96.v `
        user_source/hdl_source/key_video_mode.v `
        user_source/hdl_source/key_remove_shakes.v `
        user_source/hdl_source/isp/binary_threshold_96.v `
        user_source/hdl_source/isp/isp_top.v `
        user_source/hdl_source/isp/data128_96/data128_96.v `
        user_source/hdl_source/data_96bit_to_128bit.v `
        verification/edge_modes/tb_isp_modes.sv
    if ($LASTEXITCODE -ne 0) { throw 'ISP vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $ispLibrary tb_isp_modes `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/edge_modes/isp_simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'ISP vsim failed' }
    if (!(Select-String -Quiet -LiteralPath verification/edge_modes/isp_simulation.log -Pattern 'PASS: ISP normal/binary/edge/cartoon/gray mux')) {
        throw 'ISP simulation did not reach PASS'
    }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv verification/edge_modes/tb_mode_osd.sv
    if ($LASTEXITCODE -ne 0) { throw 'OSD vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $library tb_mode_osd `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/edge_modes/osd_simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'OSD vsim failed' }
    if (!(Select-String -Quiet -LiteralPath verification/edge_modes/osd_simulation.log -Pattern 'PASS: mode OSD')) {
        throw 'OSD simulation did not reach PASS'
    }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $library tb_rgb_gain `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/edge_modes/gain_simulation.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/edge_modes/gain_simulation.log -Pattern 'PASS: RGB gains')) {
        throw 'RGB gain simulation did not reach PASS'
    }
} finally {
    Pop-Location
}
