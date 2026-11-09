param(
  [string]$HostRepo = (Join-Path $PSScriptRoot '../tests/sunnypilot_spi_host.sim/repo'),
  [string]$GccBin = 'C:/Xilinx/Vivado/2024.2/tps/mingw/10.0.0/win64.o/nt/bin'
)
$ErrorActionPreference='Stop'
$sourcePath=Join-Path $HostRepo 'openpilot/system/flexray_logd'
if (!(Test-Path (Join-Path $sourcePath 'tests/test_spi_pipeline.c'))) { throw 'Apply the host SPI patch to the selected host repository first' }
$buildPath=Join-Path $PSScriptRoot '../tests/sunnypilot_spi_host.sim'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
$binary=Join-Path (Resolve-Path $buildPath).Path 'test_spi_pipeline.exe'
$oldPath=$env:PATH
Push-Location $sourcePath
try {
  $env:PATH=$GccBin+';'+$env:PATH
  & (Join-Path $GccBin 'gcc.exe') -std=gnu11 -Wall -Wextra -Werror -DEXPORT_DLL -Itests/mocks -I. -Ilibftdi tests/test_spi_pipeline.c flexray_reader.c libftdi/ftdispi.c libftdi/ftdispi_usb.c -o $binary -pthread
  if ($LASTEXITCODE -ne 0) { throw 'Host SPI mock compile failed' }
  & $binary
  if ($LASTEXITCODE -ne 0) { throw 'Host SPI mock regressions failed' }
} finally { $env:PATH=$oldPath;Pop-Location }
