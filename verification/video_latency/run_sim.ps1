param([string]$ModelSimBin = 'C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $library = 'verification/video_latency/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $library
    if ($LASTEXITCODE -ne 0) { throw 'latency vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv `
        user_source/hdl_source/latency_cdc.v `
        user_source/hdl_source/latency_timebase.v `
        user_source/hdl_source/latency_capture.v `
        user_source/hdl_source/latency_slots.v `
        user_source/hdl_source/latency_osd.v `
        user_source/hdl_source/latency_system.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        user_source/hdl_source/video_in.v `
        user_source/hdl_source/video_out.v `
        user_source/hdl_source/design_top_wrapper.v `
        verification/video_latency/tb_video_latency.sv `
        verification/video_latency/tb_latency_system.sv `
        verification/video_latency/tb_latency_full_frame.sv
    if ($LASTEXITCODE -ne 0) { throw 'latency vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/video_latency/unit.wlf -lib $library tb_video_latency `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/video_latency/simulation.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/video_latency/simulation.log -Pattern 'PASS: latency CDC')) {
        throw 'latency simulation failed or PASS missing'
    }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/video_latency/system.wlf -lib $library tb_latency_system `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/video_latency/system_simulation.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/video_latency/system_simulation.log -Pattern 'PASS: integrated latency')) {
        throw 'integrated latency simulation failed or PASS missing'
    }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/video_latency/startup.wlf -lib $library tb_latency_system `
        -gSTARTUP_DELAY_NS=100000 `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/video_latency/startup_simulation.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/video_latency/startup_simulation.log -Pattern 'PASS: delayed CSI clock startup')) {
        throw 'delayed CSI startup simulation failed or PASS missing'
    }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/video_latency/full_frame.wlf -lib $library tb_latency_full_frame `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' `
        -l verification/video_latency/full_frame_simulation.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/video_latency/full_frame_simulation.log -Pattern 'PASS: real 1280x720')) {
        throw 'full-frame latency simulation failed or PASS missing'
    }
} finally { Pop-Location }
