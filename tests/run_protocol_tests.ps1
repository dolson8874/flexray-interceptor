param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$buildPath = Join-Path $PSScriptRoot 'protocol.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $sourcePath 'can_pkg.vhd') (Join-Path $sourcePath 'can_tx.vhd') (Join-Path $sourcePath 'can_rx.vhd') (Join-Path $PSScriptRoot 'can_reference_pkg.vhd') (Join-Path $PSScriptRoot 'can_protocol_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.can_protocol_tb -s can_protocol
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') can_protocol -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY protocol failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Protocol tests failed' }
} finally { Pop-Location }
