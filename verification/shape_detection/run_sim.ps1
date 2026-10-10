param([string]$ModelSimBin='C:\altera\14.1\modelsim_ase\win32aloem', [switch]$DiagnoseUpstream, [string]$Only='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $lib='verification/shape_detection/work'
    & (Join-Path $ModelSimBin 'vlib.exe') $lib
    if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $lib -sv `
        user_source/hdl_source/isp/shape_contour_classifier.v `
        user_source/hdl_source/isp/detection_result_stabilizer.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        user_source/hdl_source/isp/color_reduce_rgb96.v `
        user_source/hdl_source/isp/color_shape_detect.v `
        user_source/hdl_source/isp/detection_overlay_rgb96.v `
        user_source/hdl_source/isp/detection_mask_osd_rgb96.v `
        verification/shape_detection/tb_color_reduce.sv `
        verification/shape_detection/tb_color_shape.sv `
        verification/shape_detection/tb_detection_overlay.sv `
        verification/shape_detection/tb_shape_contour.sv `
        verification/shape_detection/tb_detection_stability.sv `
        verification/shape_detection/tb_detection_mask.sv
    if($LASTEXITCODE -ne 0) { throw 'Detection vlog failed' }
    $tests=@('tb_color_reduce','tb_color_shape','tb_detection_overlay','tb_shape_contour','tb_detection_stability','tb_detection_mask')
    if($Only) {
        if($Only -notin $tests) { throw "Unknown test: $Only" }
        $tests=@($Only)
    }
    foreach($tb in $tests) {
        $log="verification/shape_detection/$tb.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib $tb `
            -do 'onerror {quit -code 1}; run -all; quit -code 0' -l $log
        if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath $log -Pattern 'PASS:')) {
            throw "$tb did not pass"
        }
    }
    if($Only) { return }
    $ispLib='verification/shape_detection/work_isp'
    & (Join-Path $ModelSimBin 'vlib.exe') $ispLib
    if($LASTEXITCODE -ne 0) { throw 'ISP vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -work $ispLib -sv `
        user_source/hdl_source/isp/color_gain_rgb96.v `
        user_source/hdl_source/isp/saturation_rgb96.v `
        user_source/hdl_source/isp/grayscale_rgb96.v `
        user_source/hdl_source/isp/anlogic_logo_words.v `
        user_source/hdl_source/isp/logo_osd_rgb96.v `
        user_source/hdl_source/isp/osd_char_lib.v `
        user_source/hdl_source/isp/mode_osd_rgb96.v `
        user_source/hdl_source/isp/shape_contour_classifier.v `
        user_source/hdl_source/isp/detection_result_stabilizer.v `
        user_source/hdl_source/isp/color_reduce_rgb96.v `
        user_source/hdl_source/isp/color_shape_detect.v `
        user_source/hdl_source/isp/detection_overlay_rgb96.v `
        user_source/hdl_source/isp/detection_mask_osd_rgb96.v `
        user_source/hdl_source/isp/cartoon_96.v `
        user_source/hdl_source/isp/edge_detect_96.v `
        user_source/hdl_source/key_video_mode.v `
        user_source/hdl_source/key_remove_shakes.v `
        user_source/hdl_source/isp/binary_threshold_96.v `
        user_source/hdl_source/isp/isp_top.v `
        user_source/hdl_source/isp/data128_96/data128_96.v `
        user_source/hdl_source/data_96bit_to_128bit.v `
        verification/edge_modes/tb_isp_modes.sv `
        verification/shape_detection/tb_detection_isp.sv
    if($LASTEXITCODE -ne 0) { throw 'ISP detection vlog failed' }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $ispLib tb_detection_isp `
        -do 'onerror {quit -code 1}; run -all; quit -code 0' -l verification/shape_detection/full_isp.log
    if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/shape_detection/full_isp.log -Pattern 'PASS:')) {
        throw 'Full ISP detection did not pass'
    }
    # Optional upstream diagnostic; known X-valued boxes in ModelSim 10.3c.
    # This is NOT a passing cross-validation or a runtime dependency.
    if($DiagnoseUpstream) {
        $ref='verification/shape_detection/reference/linkruncca-main/src/verilog'
        if(!(Test-Path -LiteralPath "$ref/LinkRunCCA.v")) { throw 'Fetch upstream reference first; see README.md' }
        $refLib='verification/shape_detection/work_upstream'
        & (Join-Path $ModelSimBin 'vlib.exe') $refLib
        if($LASTEXITCODE -ne 0) { throw 'Upstream vlib failed' }
        $refFiles=Get-ChildItem -LiteralPath $ref -Filter '*.v' | ForEach-Object { $_.FullName }
        & (Join-Path $ModelSimBin 'vlog.exe') -work $refLib -sv "+incdir+$ref" $refFiles verification/shape_detection/tb_linkrun_reference.sv
        if($LASTEXITCODE -ne 0) { throw 'Upstream vlog failed' }
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $refLib tb_linkrun_reference `
            -do 'onerror {quit -code 1}; run -all; quit -code 0' -l verification/shape_detection/upstream.log
        if($LASTEXITCODE -ne 0 -or !(Select-String -Quiet -LiteralPath verification/shape_detection/upstream.log -Pattern 'PASS:')) {
            throw 'Upstream reference did not pass'
        }
    }
} finally { Pop-Location }
