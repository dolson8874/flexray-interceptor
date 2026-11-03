param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$hdlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$buildPath = Join-Path $PSScriptRoot 'remaining_review.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $hdlPath 'flexray_pkg.vhd') (Join-Path $hdlPath 'flexray_rx.vhd') (Join-Path $hdlPath 'flexray_torque_intercept.vhd') (Join-Path $PSScriptRoot 'flexray_reference_pkg.vhd') (Join-Path $PSScriptRoot 'review_remaining_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') work.review_remaining_tb -s review_remaining
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') review_remaining -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY remaining_flexray failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Remaining FlexRay regressions failed' }
    Copy-Item -LiteralPath xsim.log -Destination flexray_result.log
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $hdlPath 'can_pkg.vhd') (Join-Path $hdlPath 'can_rx.vhd') (Join-Path $hdlPath 'can_tx.vhd') (Join-Path $hdlPath 'joystick_decoder.vhd') (Join-Path $PSScriptRoot 'can_reference_pkg.vhd') (Join-Path $PSScriptRoot 'review_can_length_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'CAN compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') work.review_can_length_tb -s review_can_length
    if ($LASTEXITCODE -ne 0) { throw 'CAN elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') review_can_length -runall
    if ($LASTEXITCODE -ne 0) { throw 'CAN simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    Copy-Item -LiteralPath xsim.log -Destination can_length_result.log
    if ($simulationLog -notmatch 'TEST_SUMMARY can_length failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'CAN length regressions failed' }
} finally { Pop-Location }
