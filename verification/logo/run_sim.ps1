param([string]$ModelSimBin='C:\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $library='verification/logo/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $library
    if($LASTEXITCODE -ne 0) {throw 'Logo vlib failed'}
    & (Join-Path $ModelSimBin 'vlog.exe') -work $library -sv `
        user_source/hdl_source/anlogic_logo_rom.v `
        user_source/hdl_source/isp/anlogic_logo_words.v `
        user_source/hdl_source/isp/logo_osd_rgb96.v `
        verification/logo/tb_logo.sv
    if($LASTEXITCODE -ne 0) {throw 'Logo compile failed'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -wlf verification/logo/simulation.wlf -lib $library tb_logo `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' -l verification/logo/simulation.log
    if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/logo/simulation.log -Pattern 'PASS: three-colour logo')) {
        throw 'Logo simulation failed or PASS missing'
    }
} finally {Pop-Location}
