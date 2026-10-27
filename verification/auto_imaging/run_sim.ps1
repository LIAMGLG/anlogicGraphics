param([string]$ModelSimBin='C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $lib='verification/auto_imaging/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $lib
    if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $lib -sv `
        user_source/hdl_source/awb.v user_source/hdl_source/signal_delay.v `
        user_source/hdl_source/isp/image_stats_rgb96.v `
        user_source/hdl_source/isp/color_gain_rgb96.v user_source/hdl_source/isp/saturation_rgb96.v `
        user_source/hdl_source/isp/osd_char_lib.v user_source/hdl_source/isp/mode_osd_rgb96.v `
        user_source/hdl_source/uiisp_beta/ae_set.v user_source/hdl_source/latency_cdc.v `
        verification/auto_imaging/tb_auto_imaging.sv verification/auto_imaging/tb_exposure_osd.sv
    if($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    foreach($tb in @('tb_auto_imaging','tb_ae_control','tb_natural_color','tb_exposure_osd')) {
        $log="verification/auto_imaging/$tb.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib $tb `
            -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
        if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS:')) {
            throw "$tb failed"
        }
    }
} finally { Pop-Location }
