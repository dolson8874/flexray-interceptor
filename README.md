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


