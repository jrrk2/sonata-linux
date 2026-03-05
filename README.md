# sonata-linux

Top-level repo for Linux on the lowRISC Sonata FPGA board (LiteX + VexRiscv SMP).

## Quick Start

```bash
git clone --recursive <this-repo>
cd sonata-linux
make setup      # builds toolchain, extracts kernel + opensbi (~30 min)
make            # builds flashxip.bin + SD card boot files
make sdcard     # copies files to /tmp/sonata-sdcard/
```

## Submodules

| Submodule | Purpose |
|-----------|---------|
| `sonata-system` | FPGA RTL, device tree, kernel config, boot scripts |
| `linux-on-litex-vexriscv` | LiteX Linux orchestrator, board definitions, patches |
| `litex` | LiteX SoC framework |
| `litex-boards` | Board platform + target definitions |
| `migen` | Migen HDL (LiteX dependency) |
| `litespi` | SPI flash controller |
| `litesdcard` | SD card controller |
| `litedram` | DRAM controller (HyperRAM) |
| `pythondata-cpu-vexriscv-smp` | VexRiscv SMP CPU verilog |
| `buildroot` | Cross toolchain + rootfs + kernel/opensbi source |

## Build Outputs (in `out/`)

| File | Description |
|------|-------------|
| `flashxip.bin` | Combined flash image: kernel + OpenSBI + rootfs |
| `rv32.dtb` | Device tree blob (for OpenSBI) |
| `xipjump.bin` | 12-byte BIOS-to-OpenSBI trampoline |
| `boot.json` | BIOS boot load map |

## SD Card Contents (for XIP boot)

```
sonata.bit      FPGA bitstream
boot.json       BIOS load map
rv32.dtb        Device tree for OpenSBI
xipjump.bin     Trampoline to OpenSBI in flash
```

## Flash Layout (flashxip.bin)

```
Offset    Content
0x000000  xipImage (kernel, XIP from flash)
0x780000  OpenSBI fw_jump (XIP from flash, .data/.bss in HyperRAM)
0x800000  rootfs.romfs (mounted read-only)
```

## Architecture

- FPGA: Xilinx Artix-7 XC7A50T @ 50MHz
- CPU: VexRiscv RV32IMA SMP (2 cores), sv32 MMU
- RAM: 8MB HyperRAM
- Flash: 32MB W25Q256 SPI NOR (XIP with 64KB cache)
- Boot: BIOS → xipjump → OpenSBI (flash) → Linux (flash)
- Kernel uses CONFIG_BUILTIN_DTB=y (required for SMP on hardware)
