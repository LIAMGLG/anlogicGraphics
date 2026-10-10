param([string]$TdBin='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe', [switch]$Implement)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work=Join-Path $PSScriptRoot 'work_syn_v4'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$project=New-Object Xml.XmlDocument
# TD project syntax includes raw '&' and '::' tag names, not strict XML.
$projectText=([IO.File]::ReadAllText((Join-Path $root 'td_project/camera_to_dsi_display.al'))).Replace('UsedInP&R','UsedInP&amp;R').Replace('::','__TD_NS__')
$project.LoadXml($projectText)
$project.DocumentElement.RemoveAttribute('Path')
$project.SelectSingleNode('/Project/Name').InnerText='shape_rotation_check'
foreach($file in $project.SelectNodes('//Source_Files//File[@Path]')) {
    $path=$file.GetAttribute('Path')
    if(![IO.Path]::IsPathRooted($path)) { $path=Join-Path (Join-Path $root 'td_project') $path }
    $file.SetAttribute('Path',[IO.Path]::GetFullPath($path).Replace('\','/'))
}
$projectFile=Join-Path $work 'shape_rotation_check.prj'
$project.Save($projectFile)
[IO.File]::WriteAllText($projectFile,([IO.File]::ReadAllText($projectFile)).Replace('UsedInP&amp;R','UsedInP&R').Replace('__TD_NS__','::'),(New-Object Text.UTF8Encoding($false)))
$r=$root.Replace('\','/')
$w=$work.Replace('\','/')
$tcl=@"
cd {$w}
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project shape_rotation_check.prj
elaborate -top design_top_wrapper
read_adc {$r/user_source/constraints_source/pin.adc}
read_ip_adc -ip ddr2 -file {$r/user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc}
read_sdc {$r/td_project/camera_to_dsi_display.sdc}
read_sdc -ip ddr2 {$r/user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc}
read_sdc -ip w128_d512_fifo {$r/user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl}
optimize_rtl
report_area -file shape_rotation_check_rtl.area
optimize_gate -packarea shape_rotation_check_gate.area
report_timing_summary -file shape_rotation_check_gate.timing
export_db shape_rotation_check_gate.db
"@
if($Implement) {
    $tcl+=@"

commit_param -step place
place
update_timing -mode manhattan
report_timing_summary -file shape_rotation_check_place.timing
export_db shape_rotation_check_place.db
commit_param -step route
route
update_timing -mode final
report_area -io_info -file shape_rotation_check_phy.area
report_timing_summary -file shape_rotation_check_pr.timing
export_db shape_rotation_check_pr.db
commit_param -step bitgen
bitgen -bit shape_mask_v4.bit
"@
}
$tcl+="`nexit`n"
$script=Join-Path $work 'shape_rotation_check.tcl'
[IO.File]::WriteAllText($script,$tcl,(New-Object Text.UTF8Encoding($false)))
Push-Location $root
try {
    $startedAt=Get-Date
    & $TdBin $script.Replace('\','/') > (Join-Path $work 'synthesis.log')
    if($LASTEXITCODE -ne 0) { throw 'TD synthesis failed; see work_syn_v4/synthesis.log' }
    $timing=Join-Path $work 'shape_rotation_check_gate.timing'
    if(!(Test-Path -LiteralPath $timing) -or (Get-Item -LiteralPath $timing).LastWriteTime -lt $startedAt) {
        throw 'No fresh timing report produced; inspect synthesis.log'
    }
    Get-Content -LiteralPath $timing -TotalCount 30
    Get-Content -LiteralPath (Join-Path $work 'shape_rotation_check_gate.area') -TotalCount 36
    $timingText=[IO.File]::ReadAllText($timing)
    foreach($check in @('SWNS','HWNS')) {
        $match=[regex]::Match($timingText,$check+':\s*(-?[0-9.]+)ns')
        if(!$match.Success -or [double]$match.Groups[1].Value -lt 0) { throw "$check check failed; inspect timing report" }
    }
    $areaText=[IO.File]::ReadAllText((Join-Path $work 'shape_rotation_check_gate.area'))
    foreach($resource in @('slice\*','eram','dsp')) {
        $match=[regex]::Match($areaText,'#'+$resource+'\s+(\d+)\s+out of\s+(\d+)')
        if(!$match.Success -or [int]$match.Groups[1].Value -gt [int]$match.Groups[2].Value) {
            throw "$resource capacity check failed; inspect area report"
        }
    }
    if($Implement) {
        $finalTiming=Join-Path $work 'shape_rotation_check_pr.timing'
        $bit=Join-Path $work 'shape_mask_v4.bit'
        foreach($artifact in @($finalTiming,$bit)) {
            if(!(Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).LastWriteTime -lt $startedAt) {
                throw "No fresh implementation artifact: $artifact"
            }
        }
        $finalText=[IO.File]::ReadAllText($finalTiming)
        foreach($check in @('SWNS','HWNS')) {
            $match=[regex]::Match($finalText,$check+':\s*(-?[0-9.]+)ns')
            if(!$match.Success -or [double]$match.Groups[1].Value -lt 0) { throw "Final $check check failed" }
        }
        Get-Content -LiteralPath $finalTiming -TotalCount 30
        Get-FileHash -LiteralPath $bit -Algorithm SHA256
    }
} finally { Pop-Location }
