param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$newPath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new'
$buildPath = Join-Path $PSScriptRoot 'log_diagnostics.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path $VivadoBin '../data/verilog/src/glbl.v')
    if ($LASTEXITCODE -ne 0) { throw 'Global model compile failed' }
    $files = @('can_pkg.vhd','flexray_pkg.vhd','can_tx.vhd','can_rx.vhd','joystick_decoder.vhd') | ForEach-Object { Join-Path $sourcePath $_ }
    $files += @('flexray_can_queue.vhd','flexray_log_can_diagnostics.vhd','can_telemetry_mux.vhd') | ForEach-Object { Join-Path $newPath $_ }
    $files += @('can_reference_pkg.vhd','log_diagnostics_tb.vhd') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 @files
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.log_diagnostics_tb work.glbl -L xpm -s log_diagnostics
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') log_diagnostics -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY log_diagnostics failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Logging diagnostics tests failed' }
} finally { Pop-Location }
