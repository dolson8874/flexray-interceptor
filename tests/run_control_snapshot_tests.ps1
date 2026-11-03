param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $PSScriptRoot 'control_snapshot.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new/control_snapshot.vhd') (Join-Path $PSScriptRoot 'control_snapshot_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.control_snapshot_tb -s control_snapshot
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') control_snapshot -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY control_snapshot failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Control snapshot tests failed' }
} finally { Pop-Location }
