param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$newPath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new'
$buildPath = Join-Path $PSScriptRoot 'integration.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path $VivadoBin '../data/verilog/src/glbl.v')
    if ($LASTEXITCODE -ne 0) { throw 'Global model compile failed' }
    $files = @('can_pkg.vhd','flexray_pkg.vhd','can_tx.vhd','can_rx.vhd','joystick_decoder.vhd','flexray_rx.vhd') | ForEach-Object { Join-Path $sourcePath $_ }
    $files += @('flexray_can_queue.vhd','flexray_can_telemetry.vhd','control_snapshot.vhd') | ForEach-Object { Join-Path $newPath $_ }
    $files += @('can_reference_pkg.vhd','flexray_reference_pkg.vhd','telemetry_integration_tb.vhd') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 @files
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.telemetry_integration_tb work.glbl -L xpm -s telemetry_integration
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') telemetry_integration -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY integration failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Integration tests failed' }
} finally { Pop-Location }
