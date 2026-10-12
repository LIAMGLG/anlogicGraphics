param([string]$ModelSimBin='C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $lib='verification/resources/work_font'
    & (Join-Path $ModelSimBin 'vlib.exe') $lib
    if($LASTEXITCODE -ne 0) {throw 'Font vlib failed'}
    & (Join-Path $ModelSimBin 'vlog.exe') -work $lib -sv `
        user_source/hdl_source/isp/osd_char_lib.v verification/resources/tb_font_rows.sv
    if($LASTEXITCODE -ne 0) {throw 'Font compile failed'}
    $log='verification/resources/work_font.log'
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/resources/work_font.wlf `
        -lib $lib tb_font_rows -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
    if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS: all 4096')) {
        throw 'Font reference mismatch or PASS missing'
    }
} finally {Pop-Location}
