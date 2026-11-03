param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $PSScriptRoot 'queue.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path $VivadoBin '../data/verilog/src/glbl.v')
    if ($LASTEXITCODE -ne 0) { throw 'Global model compile failed' }
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874/flexray_pkg.vhd') (Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new/flexray_can_queue.vhd') (Join-Path $PSScriptRoot 'flexray_can_queue_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') work.flexray_can_queue_tb work.glbl -L xpm -s flexray_can_queue
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') flexray_can_queue -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY queue failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Queue tests failed' }
} finally { Pop-Location }
