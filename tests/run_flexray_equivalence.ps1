param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin',
    [string]$BaselineRef = 'cb31f52'
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$sourceDir = 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
$buildPath = Join-Path $PSScriptRoot 'equivalence.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
$baseline = & git -C $repoPath show "${BaselineRef}:${sourceDir}/flexray_torque_intercept.vhd"
if ($LASTEXITCODE -ne 0) { throw 'Cannot read baseline' }
$baselineText = ($baseline -join "`n").Replace('flexray_torque_intercept', 'baseline_torque_intercept')
# Compare normal behavior with the same explicitly disabled LCA test mode.
$baselineText = $baselineText.Replace('constant TEST_LCA : boolean := true;', 'constant TEST_LCA : boolean := false;')
[IO.File]::WriteAllText((Join-Path $buildPath 'baseline.vhd'), $baselineText, (New-Object System.Text.UTF8Encoding($false)))
$baselineCommit = & git -C $repoPath rev-parse $BaselineRef
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve baseline revision' }
[IO.File]::WriteAllText((Join-Path $buildPath 'baseline_revision.txt'), $baselineCommit, (New-Object System.Text.UTF8Encoding($false)))
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $repoPath "$sourceDir/flexray_pkg.vhd") baseline.vhd (Join-Path $repoPath "$sourceDir/flexray_torque_intercept.vhd") (Join-Path $PSScriptRoot 'flexray_timing_equivalence_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.flexray_timing_equivalence_tb -s flexray_equivalence
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') flexray_equivalence -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY equivalence failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'Equivalence failed' }
} finally { Pop-Location }
