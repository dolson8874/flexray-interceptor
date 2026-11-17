SPI/USB host patch

Source5 extension (2026-11-17)
------------------------------
Patch: source5-native.patch
Target: dolson8874/sunnypilot, lrmaster-SP-flexraylog-v2-wip
Tested base: 97efb304e81f60fe8f9b8c23da5579807d8f2ca3

CA80/CA90/CAA0 are wire buses 0/1/2 -> Event.can sources 4/5/6.
Source5 contains original DADC candidate IDs 0x1F/0x31/0x0D, regardless of
actual payload changes. Frame IDs and flags/cycle/payload/CRC body are retained.
The patch accepts CA90 and tracks its native frame/byte totals separately as
dadc_original_frames/dadc_original_wire_bytes in flexray_stats. It preserves
source5 through startup buffering and capture freshness without adding schema
fields or inflating the existing source4/source6 health counters. The UI still
shows its existing source4/source6 rates; source5 totals are in native logs.
Physical CAN, safety, carcontroller and the cruise observer are not modified.

Apply only in the authoritative host repository after reviewing its current
branch/changes. This patch is NOT an automatic deployment or a replacement
for unrelated host work:
  git apply --check PATH_TO/source5-native.patch
  git apply PATH_TO/source5-native.patch

Offline Windows verification from this FPGA repository:
  python tests/test_source5_host.py --host-repo PATH_TO_SUNNYPILOT
This reconstructs the pinned base in tests/source5_host.sim, checks and applies
the exact patch there, compiles/runs native decoder tests with GCC warnings as
errors, and tests the actual Python mapper/status/startup code through AST
extraction. It never modifies the supplied host repository. Full cereal/rlog/IPC
and Linux application tests must additionally run in the host's build environment.
No firmware programming, device transfer or GitHub push is performed by this test.

Earlier SPI/USB patch
---------------------

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
