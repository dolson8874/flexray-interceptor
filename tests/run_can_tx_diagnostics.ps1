param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin',
    [string]$SourceRef = 'working'
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $PSScriptRoot 'can_tx_diagnostics.sim'
$sourceDir = 'flexray-interceptor-vivado.srcs/sources_1/imports/flexray-interceptor-dolson8874'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($name in @('can_pkg.vhd', 'can_tx.vhd')) {
    if ($SourceRef -eq 'working') {
        $contents = Get-Content (Join-Path $repoPath "$sourceDir/$name")
    } else {
        $contents = & git -C $repoPath show "${SourceRef}:${sourceDir}/${name}"
        if ($LASTEXITCODE -ne 0) { throw "Cannot read $name from $SourceRef" }
    }
    [System.IO.File]::WriteAllLines((Join-Path $buildPath $name), [string[]]$contents, $utf8)
}
$revision = if ($SourceRef -eq 'working') { 'HEAD' } else { $SourceRef }
$commit = & git -C $repoPath rev-parse $revision
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source revision' }
[System.IO.File]::WriteAllText((Join-Path $buildPath 'source_revision.txt'), "$SourceRef $commit", $utf8)
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 can_pkg.vhd can_tx.vhd (Join-Path $PSScriptRoot 'can_tx_diagnostics_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'VHDL compilation failed' }
    & (Join-Path $VivadoBin 'xelab.bat') work.can_tx_diagnostics_tb -s can_tx_diagnostics
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') can_tx_diagnostics -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simOutput = Get-Content xsim.log -Raw
    if ($simOutput -notmatch 'TEST_SUMMARY failures=0\b' -or $simOutput -match '(?m)^(Error|Failure|Fatal):') {
        throw 'CAN diagnostics found failures or did not complete; inspect xsim.log'
    }
} finally {
    Pop-Location
}
