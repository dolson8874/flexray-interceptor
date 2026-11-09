param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $PSScriptRoot 'spi_timing_review.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 (Join-Path $repoPath 'flexray-interceptor-vivado.srcs/sources_1/new/SPI_SLAVE.vhd') (Join-Path $PSScriptRoot 'spi_timing_review_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.spi_timing_review_tb -s spi_timing_review
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') spi_timing_review -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY spi_timing_review supported_failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw '7.5 MHz ideal SPI characterization failed' }
} finally { Pop-Location }
