SPI/USB host patch

Target: dolson8874/sunnypilot, lrmaster-SP-flexraylog-v2
Base: 6b0167ab12affb2f777073e2c5e92b755bab5c2c
Patch: sunnypilot-spi-usb.patch (apply from host repository root).

The authoritative single-file handoff is docs/sunnypilot-flexray-handoff.txt.
It embeds this patch and describes the remaining bidirectional log/CAN work.
Do not overwrite existing changes or push/deploy without user instructions.

Validated: clean baseline patch application and actual patched C driver/reader
using native GCC -Wall -Wextra -Werror and a mocked libusb/FTDI transport.
The C tests cover clock settings, status removal, partial timeout/fatal data,
bounded ordered requests, recovery, strict command writes, finish/idle GPIO,
and maximum 16-bit read sizes.

Linux: cd openpilot/system/flexray_logd
       make tests/test_spi_pipeline
       ./tests/test_spi_pipeline
       make test
Windows local mock runner: scripts/test_sunnypilot_spi_patch.ps1 -HostRepo PATH

Not validated here: full Linux application build, real USB/board throughput,
electrical timing, or vehicle behavior. No GitHub push has been performed.
