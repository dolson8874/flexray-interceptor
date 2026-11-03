param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$hdlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$buildPath = Join-Path $PSScriptRoot 'bounds.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $hdlPath 'flexray_pkg.vhd') (Join-Path $hdlPath 'flexray_rx.vhd') (Join-Path $hdlPath 'flexray_torque_intercept.vhd') (Join-Path $PSScriptRoot 'flexray_reference_pkg.vhd') (Join-Path $PSScriptRoot 'flexray_bounds_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.flexray_bounds_tb -s flexray_bounds
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') flexray_bounds -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY flexray_bounds failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Frame bound regressions failed' }
} finally { Pop-Location }
