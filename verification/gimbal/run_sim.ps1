param([string]$ModelSimBin='C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $lib='verification/gimbal/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $lib
    if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $lib -sv user_source/hdl_source/red_rect_gimbal.v verification/gimbal/tb_red_rect_gimbal.sv verification/gimbal/tb_default_pwm.sv verification/gimbal/tb_gimbal_settle.sv verification/gimbal/tb_pd_rate.sv verification/gimbal/tb_gimbal_limits.sv
    if($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    foreach($tb in @('tb_red_rect_gimbal','tb_default_pwm','tb_gimbal_settle','tb_pd_rate','tb_gimbal_limits')) {
        $log="verification/gimbal/$tb.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib $tb -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
        if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS:')) { throw 'Gimbal simulation failed' }
    }
    $log='verification/gimbal/feedback_slow.log'
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib tb_gimbal_settle -gDELAY=5 -gCADENCE=4 '-gSERVO_ALPHA=0.25' -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
    if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS:')) { throw 'Slow feedback simulation failed' }
} finally { Pop-Location }
