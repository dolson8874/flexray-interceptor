# 🔐 Safety & Legal Disclaimer

This code is for research and development only.
Use in live vehicles must comply with local laws and safety standards.
Any damage or consequences are at the user’s responsibility.



# FlexRay Interceptor (XA7S50 · Xilinx Automotive)

Reference implementation of a **FlexRay MITM (man-in-the-middle) interceptor/logger** based on the Xilinx XA7S50 (Spartan-7 Automotive).  
The design places two FlexRay PHYs between vehicle bus segments to provide **transparent pass-through**, while the FPGA performs **frame detection, validation, and modification**.  

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)
[![Vivado](https://img.shields.io/badge/Vivado-2024.2-FFCC00.svg)](#-development-environment)
[![FPGA](https://img.shields.io/badge/FPGA-XA7S50-blue.svg)](#-hardware-overview)


## ✨ Features

- **MITM pass-through**: Transparent bridge between Port-A (vehicle) and Port-B (DADC)
- **Frame-level processing**: BSS/TSS/FSS sync → header/payload parsing → CRC check
- **Selective modification**: On-the-fly field or payload rewrite rules
- **Reliable logging**: Timestamp + raw/PDU dual logging, backpressure support
- **Host I/O**: FT4232HAQ  Channel A (JTAG) , Channel B SPI  for log streaming


## 🧰 Hardware Overview

- **FPGA**: Xilinx **XA7S50** 
- **FlexRay PHY**: NXP **TJA1081TS** × 4 *(Port-A/Port-B/Port-C/Port-D)*
  - Interface: `TXD`, `TXEN`, `RXD`
- **I/O/Debug**: **FT4232HA** (JTAG + MPSSE/SPI)


## 🛠 Development Environment

- **Vivado**: 2024.2  
- **Language**: VHDL  
- **JTAG**: FT4232HA (MPSSE) Vivado Hardware Manager  

<br>

# 🛠 How to use
1. Clone
   - git clone -b lrmaster-v2 https://github.com/dolson8874/flexray-interceptor.git

2. Open th Project
   - Launch Vivado → **File ▸ Open Project…**

3. Create HDL Wrapper (for Block Design) 
   - In **Sources**, open the Block Design
   - **Tools ▸ Create HDL Wrapper...**
   - Select **Let Vivado manage wrapper and auto-update** → **OK**
   
4. Set as Top
   - In **Sources**, right-click the generated `bendbeam_wrapper.vhd` → **Set as Top**.

5. Run Synthesis / Implementation / Bitstream
   - Flow Navigator: **Run Synthesis** (optionally Open Synthesized Design)
   - **Run Implementation**
   - **Generate Bitstream**

6. Generate a Memory Configuration File (.mcs / .bin)
   - **File ▸ Generate Memory Configuration File…**
   - **Format: MCS (common for SPI flashes) or BIN**
   - **Memory Part**: mt25ql128-spi-x1_x2_x4
   - **Interface**: SPIx4
   - **Load bitstream**
   - Choose an output path and Generate.
   - Check overwrite 

<br><br>

# FPGA Pin map
| Name        | XA7S50 Pin | Part        | Signal/Notes |
| ----------- | ---------- | ----------- | ------------ |
| CLK         | R2         | OSC 12MHz   |              |
| RESET out   | J6         |             |              |
| DONE        | V8         | LED         | D1           |
| TCK         | D9         | FT4232HAQ A | ADBUS0       |
| TDI         | R9         | FT4232HAQ A | ADBUS1       |
| TDO         | T8         | FT4232HAQ A | ADBUS2       |
| TMS         | T9         | FT4232HAQ A | ADBUS3       |
| SCLK        | M167       | FT4232HAQ B | BDBUS0       |
| MOSI        | M17        | FT4232HAQ B | BDBUS1       |
| MISO        | M18        | FT4232HAQ B | BDBUS2       |
| NCS         | N18        | FT4232HAQ B | BDBUS3       |
| CDBUS0      | B13        | FT4232HAQ C | CDBUS0       |
| CDBUS1      | A13        | FT4232HAQ C | CDBUS1       |
| CDBUS2      | B14        | FT4232HAQ C | CDBUS2       |
| CDBUS3      | A13        | FT4232HAQ C | CDBUS3       |
| CDBUS4      | B15        | FT4232HAQ C | CDBUS4       |
| CDBUS5      | A15        | FT4232HAQ C | CDBUS5       |
| CDBUS6      | B16        | FT4232HAQ C | CDBUS6       |
| CDBUS7      | A16        | FT4232HAQ C | CDBUS7       |
| DDBUS0      | E12        | FT4232HAQ D | DDBUS0       |
| DDBUS1      | D12        | FT4232HAQ D | DDBUS1       |
| DDBUS2      | C13        | FT4232HAQ D | DDBUS2       |
| DDBUS3      | C14        | FT4232HAQ D | DDBUS3       |
| DDBUS4      | B17        | FT4232HAQ D | DDBUS4       |
| DDBUS5      | A17        | FT4232HAQ D | DDBUS5       |
| DDBUS6      | C17        | FT4232HAQ D | DDBUS6       |
| DDBUS7      | B18        | FT4232HAQ D | DDBUS7       |
| LED1        | V16        | LED         | D7           |
| LED2        | U15        | LED         | D8           |
| LED3        | T15        | LED         | D9           |
| LED4        | R15        | LED         | D10          |
| LED5        | V17        | LED         | D11          |
| FR0\_TXD    | K4         | TJA1081     | TXD          |
| FR0\_RXD    | L4         | TJA1081     | RXD          |
| FR0\_TXEN   | K3         | TJA1081     | TXEN         |
| FR1\_TXD    | K2         | TJA1081     | TXD          |
| FR1\_RXD    | K1         | TJA1081     | RXD          |
| FR1\_TXEN   | L1         | TJA1081     | TXEN         |
| FR2\_TXD    | K6         | TJA1081     | TXD          |
| FR2\_RXD    | L6         | TJA1081     | RXD          |
| FR2\_TXEN   | L5         | TJA1081     | TXEN         |
| FR3\_TXD    | M4         | TJA1081     | TXD          |
| FR3\_RXD    | M6         | TJA1081     | RXD          |
| FR3\_TXEN   | M5         | TJA1081     | TXEN         |
| CAN\_TX     | M3         | ATA6561     | TXD          |
| CAN\_RX     | M2         | ATA6561     | RXD          |
| CAN\_STBY   | M1         | ATA6561     | STBY         |
| RELAY\_DRV0 | G16        | FR0 - FR1   |              |
| RELAY\_DRV1 | G17        | FR2 - FR3   |              |
| GPIO1       | N5         | SMAW200-20C | 20           |
| GPIO2       | N4         | SMAW200-20C | 19           |
| GPIO3       | P2         | SMAW200-20C | 18           |
| GPIO4       | P1         | SMAW200-20C | 17           |
| GPIO6       | R1         | SMAW200-20C | 15           |
| GPIO7       | R3         | SMAW200-20C | 14           |
| GPIO8       |            |             |              |

