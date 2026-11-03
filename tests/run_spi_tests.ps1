param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$hdlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'flexray-interceptor-vivado.srcs/sources_1/new/SPI_SLAVE.vhd'
$buildPath = Join-Path $PSScriptRoot 'spi.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 $hdlPath (Join-Path $PSScriptRoot 'spi_recovery_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --rangecheck work.spi_recovery_tb -s spi_recovery
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') spi_recovery -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $simulationLog = Get-Content xsim.log -Raw
    if ($simulationLog -notmatch 'TEST_SUMMARY spi_recovery failures=0' -or $simulationLog -match '(?m)^(Error|Failure|Fatal):') { throw 'SPI recovery regressions failed' }
} finally { Pop-Location }
