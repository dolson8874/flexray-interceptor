param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$hdlPath = Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1'
$buildPath = Join-Path $PSScriptRoot 'review_regressions.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $hdlPath 'imports/flexray-interceptor-dolson8874/flexray_pkg.vhd') (Join-Path $hdlPath 'imports/flexray-interceptor-dolson8874/flexray_rx.vhd') (Join-Path $hdlPath 'imports/flexray-interceptor-dolson8874/flexray_torque_intercept.vhd') (Join-Path $hdlPath 'new/flexray_log_dispatch.vhd') (Join-Path $PSScriptRoot 'flexray_reference_pkg.vhd') (Join-Path $PSScriptRoot 'flexray_faults_tb.vhd') (Join-Path $PSScriptRoot 'log_dispatch_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    foreach ($top in @('flexray_faults', 'log_dispatch')) {
        & (Join-Path $VivadoBin 'xelab.bat') "work.${top}_tb" -s $top
        if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
        & (Join-Path $VivadoBin 'xsim.bat') $top -runall
        if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
        $simulationLog = Get-Content xsim.log -Raw
        Copy-Item -LiteralPath xsim.log -Destination "${top}_result.log"
        if ($simulationLog -notmatch "TEST_SUMMARY $top failures=0" -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw "$top tests failed" }
    }
} finally { Pop-Location }
