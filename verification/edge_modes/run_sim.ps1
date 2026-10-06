param([string]$ModelSimBin = 'C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $library = 'verification/edge_modes/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $library
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv `
        user_source/hdl_source/isp/cartoon_96.v `
        user_source/hdl_source/isp/edge_detect_96.v `
        user_source/hdl_source/key_video_mode.v `
        user_source/hdl_source/key_remove_shakes.v `
        user_source/hdl_source/isp/binary_threshold_96.v `
        user_source/hdl_source/isp/isp_top.v `
        verification/edge_modes/tb_edge_modes.sv
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
    if (!(Select-String -Quiet -LiteralPath verification/edge_modes/isp_simulation.log -Pattern 'PASS: ISP normal/binary/edge/cartoon mux')) {
        throw 'ISP simulation did not reach PASS'
    }
} finally {
    Pop-Location
}
