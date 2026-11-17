param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin', [switch]$LogOnly)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$buildPath = Join-Path $PSScriptRoot 'frontend.sim'
& (Join-Path $VivadoBin 'vivado.bat') -mode batch -nojournal -nolog -notrace -source (Join-Path $repoPath 'scripts/prepare_frontend_sim.tcl')
if ($LASTEXITCODE -ne 0) { throw 'FIFO simulation generation failed' }
Push-Location $buildPath
try {
    $wrapper = (Get-Content fifo_model_path.txt -Raw).Trim()
    & (Join-Path $VivadoBin 'xvlog.bat') $wrapper (Join-Path $VivadoBin '../data/verilog/src/glbl.v')
    if ($LASTEXITCODE -ne 0) { throw 'FIFO wrapper compile failed' }
    $files = @('flexray_pkg.vhd','flexray_rx.vhd','flexray_log.vhd','flexray_torque_intercept.vhd') | ForEach-Object {Join-Path $sourcePath $_}
    $files += Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new/flexray_log_dispatch.vhd'
    $files += Join-Path $sourcePath 'flexray_interceptor.vhd'
    $files += @('flexray_reference_pkg.vhd','frontend_tb.vhd','source5_frontend_tb.vhd','source5_dispatch_tb.vhd') | ForEach-Object {Join-Path $PSScriptRoot $_}
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 @files
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    $top = if ($LogOnly) {'work.frontend_log_tb'} else {'work.frontend_tb'}
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck $top work.glbl -L fifo_generator_v13_2_11 -s frontend
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') frontend -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY frontend failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Frontend regressions failed' }
    Copy-Item -LiteralPath xsim.log -Destination frontend_result.log
    foreach ($case in @('source5_dispatch','source5_frontend')) {
        & (Join-Path $VivadoBin 'xelab.bat') --rangecheck "work.${case}_tb" work.glbl -L fifo_generator_v13_2_11 -s $case
        if ($LASTEXITCODE -ne 0) { throw "$case elaboration failed" }
        & (Join-Path $VivadoBin 'xsim.bat') $case -runall
        if ($LASTEXITCODE -ne 0) { throw "$case simulation failed" }
        $caseLog = Get-Content xsim.log -Raw
        Copy-Item -LiteralPath xsim.log -Destination "${case}_result.log"
        if ($caseLog -notmatch "TEST_SUMMARY $case failures=0" -or $caseLog -match '(?m)^(Error|Failure|Fatal):') { throw "$case regressions failed" }
    }
} finally { Pop-Location }
