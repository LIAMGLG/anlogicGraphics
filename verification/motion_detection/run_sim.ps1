param([string]$ModelSimBin='D:\modelsim10.4\win64')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $lib='verification/motion_detection/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $lib
    if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $lib -sv `
        user_source/hdl_source/isp/motion_detect_rgb96.v `
        user_source/hdl_source/isp/motion_overlay_rgb96.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        verification/motion_detection/tb_motion.sv
    if($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    foreach($tb in @('tb_motion','tb_motion_720p','tb_motion_overlay')) {
        $log="verification/motion_detection/$tb.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib $tb `
            -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
        if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS:')) {
            throw "$tb did not pass"
        }
    }
} finally { Pop-Location }
