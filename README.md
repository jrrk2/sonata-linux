# sonata-linux

RV32IMA Linux running XIP from flash on the [Sonata FPGA board](https://github.com/lowRISC/sonata-system),
using a LiteX SoC with dual-core VexRiscv SMP and sv32 MMU.

## Hardware

- **FPGA**: Xilinx Artix-7 (Sonata board by lowRISC)
- **CPU**: VexRiscv SMP, 2 harts, RV32IMAFD, sv32 MMU
- **Flash**: SPI NOR at `0x02000000` (kernel runs XIP from here)
- **RAM**: 8 MB HyperRAM at `0x40000000`
- **Peripherals**: UART at `0xf0001000`, MMC, SPI (KS8851 Ethernet), GPIO

## Quick start

```sh
git clone --recursive <repo-url>
cd sonata-linux
make setup      # Build toolchain, extract kernel + OpenSBI (~30 min)
make            # Build flashxip.bin + SD card boot files
```

## Flash layout (`flashxip.bin`)

```
Offset     Size    Contents
0x000000   ~5.5MB  xipImage (kernel, executes in place from flash)
0x600000   ~260KB  OpenSBI fw_jump.bin (code XIP, data in RAM)
0x6FF000   4KB     rv32.dtb (device tree blob)
0x700000   ~8MB    rootfs.romfs (read-only root filesystem)
```

## Boot sequence

1. Sonata BIOS loads `xipjump.bin` from SD card to RAM (`0x40000000`)
2. `xipjump.bin` (12 bytes) sets `a1` = DTB address in flash, jumps to OpenSBI
3. OpenSBI runs XIP from flash, relocates DTB to RAM, enters S-mode
4. Kernel runs XIP from flash, mounts romfs root from MTD

## Prerequisites

- macOS or Linux build host
- macOS: GNU coreutils (`brew install coreutils findutils gsed`)
- Device tree compiler: `dtc`
- Xilinx Vivado 2022.2+ (for FPGA bitstream only)

## Build targets

```sh
make setup           # First-time: build toolchain + extract sources
make                 # Build flashxip.bin + SD card boot files
make kernel          # Rebuild xipImage
make opensbi         # Rebuild OpenSBI
make dtb             # Rebuild device tree
make rootfs          # Regenerate rootfs.romfs from buildroot target
make flasher         # Build standalone SD-to-flash programmer (out/boot.bin)
make bitstream       # Build FPGA bitstream (requires Vivado)
make uf2             # Convert bitstream to UF2 for USB flashing
make sdcard          # Copy boot files to /tmp/sonata-sdcard/
```

## Flashing to hardware

Copy `out/flashxip.bin` to an SD card, then in the Sonata BIOS console:

```
flash_erase_range 0 <size>
flash_from_sdcard flashxip.bin
```

Or use SD card boot:

```sh
make sdcard SDCARD_OUT=/path/to/sdcard
```

This copies `flashxip.bin`, `xipjump.bin`, and `boot.json` to the SD card.

## QEMU testing

A custom QEMU with Sonata machine support is required
(multi-hart, SPI OpenTitan stub).

```sh
~/qemu-sonata/build/qemu-system-riscv32-unsigned \
  -machine sonata -smp 2 -m 32M -nographic \
  -device loader,file=out/flashxip.bin,addr=0x02000000,force-raw=on \
  -device loader,file=out/rv32.dtb,addr=0x40770000,force-raw=on \
  -device loader,file=out/xipjump.bin,addr=0x407FF000,force-raw=on
```

Login as `root` (no password). QEMU does not use the xipjump trampoline;
the CPU starts directly at OpenSBI via `-device loader`.

## TCC C compiler

The rootfs includes [TCC](https://bellard.org/tcc/) (Tiny C Compiler)
cross-compiled for RV32, enabling on-target C compilation.

### Hardware FPU support (`-mfpu`)

The TCC RV32 backend has been extended with a `-mfpu` flag that emits inline
hardware F+D floating-point instructions instead of soft-float library calls:

```sh
# On target:
tcc -mfpu -o /tmp/test /tmp/test.c
/tmp/test
```

Without `-mfpu`, TCC emits calls to libgcc soft-float functions (`__adddf3`,
`__muldf3`, etc.). With `-mfpu`, it generates `fadd.d`, `fmul.d`, etc. directly.

Supported operations: float/double arithmetic, comparisons, int32/int64-to-float
conversions, float-to-int32 truncation, float-double widening/narrowing.

**Modified TCC files:**

| File | Change |
|------|--------|
| `tinycc/tcc.h` | `fpu` field in `TCCState` |
| `tinycc/libtcc.c` | `-mfpu`/`-mno-fpu` option parsing |
| `tinycc/riscv32-gen.c` | `gen_opf_fpu()` inline FPU codegen |

### FPU stub libgcc.a

`linux/fpu-stubs/fpustub.S` provides 34 assembly functions that replace
the soft-float `libgcc.a` with thin wrappers around hardware FPU instructions.
These receive arguments in integer registers (ILP32 soft-float ABI), move them
to FPU registers, execute the hardware instruction, and return via integer
registers.

Build the stub library:

```sh
CROSS=buildroot/output/host/bin/riscv32-buildroot-linux-musl-
${CROSS}gcc -c -march=rv32imafd -mabi=ilp32 \
  -o linux/fpu-stubs/fpustub.o linux/fpu-stubs/fpustub.S
${CROSS}ar rcs linux/fpu-stubs/libgcc.a linux/fpu-stubs/fpustub.o
```

Deploy to the target as `/usr/lib/libgcc.a`.

### Building the TCC binary

Cross-compile TCC for the target:

```sh
CROSS=buildroot/output/host/bin/riscv32-buildroot-linux-musl-
${CROSS}gcc -DONE_SOURCE=1 -static -O2 -o tinycc/tcc tinycc/tcc.c -lm
```

Install into the rootfs as `/usr/bin/tcc`.

### TCC runtime files

TCC needs these files installed on the target at `/usr/lib/`:

| File | Source |
|------|--------|
| `libtcc1.a` | Cross-compile from `tinycc/lib/` (see below) |
| `runmain.o` | Cross-compile `tinycc/lib/runmain.c` |
| `libc.so` | Copy from `buildroot/output/target/lib/libc.so` |
| `libgcc.a` | FPU stubs (above) |
| `crt1.o`, `crti.o`, `crtn.o` | From buildroot sysroot |

Build `libtcc1.a` and `runmain.o`:

```sh
CROSS=buildroot/output/host/bin/riscv32-buildroot-linux-musl-
CFLAGS="-march=rv32imafd -mabi=ilp32 -O2 -I tinycc"

# libtcc1.a
for f in libtcc1.c stdatomic.c builtin.c dsohandle.c; do
  ${CROSS}gcc -c ${CFLAGS} -o tinycc/lib/${f%.c}.o tinycc/lib/$f
done
${CROSS}gcc -c ${CFLAGS} -o tinycc/lib/alloca.o tinycc/lib/alloca.S
${CROSS}ar rcs tinycc/lib/libtcc1.a \
  tinycc/lib/libtcc1.o tinycc/lib/stdatomic.o tinycc/lib/builtin.o \
  tinycc/lib/alloca.o tinycc/lib/dsohandle.o

# runmain.o
${CROSS}gcc -c ${CFLAGS} -o tinycc/lib/runmain.o tinycc/lib/runmain.c
```

### Rootfs setup for TCC

TCC hardcodes the ELF interpreter path without the `-sf` (soft-float) suffix.
Add a symlink:

```sh
BR_TARGET=buildroot/output/target
ln -sf libc.so ${BR_TARGET}/lib/ld-musl-riscv32.so.1
```

Then rebuild:

```sh
rm -f out/rootfs.romfs out/flashxip.bin
make rootfs
make
```

## Benchmarks

The rootfs includes the Whetstone double-precision benchmark at
`/etc/bench/whetstone.c`:

```sh
# On target:
tcc -mfpu -lm /etc/bench/whetstone.c -o /tmp/whet
/tmp/whet 100
```

Result on Sonata hardware (~100 MHz VexRiscv): **833 KWIPS** with hardware FPU.

## OpenSBI configuration

OpenSBI runs XIP from flash with a split memory layout:

- **Code** (`.text`, `.rodata`): execute in place from flash at `0x02600000`
- **Data** (`.data`, `.bss`, stacks, heap): in RAM at `0x407F0000` (64 KB)
- **PMP guard page**: `0x407EF000` (M-only R/X, blocks S/U access)
- **Hart count**: 2 (configured in `opensbi-xip/platform/litex/vexriscv/platform.c`)

The DTS `memory` node ends at `0x407EF000` to avoid overlapping the PMP guard
page.

## Kernel configuration

Key settings in `linux/config/xip-additions.config`:

- `CONFIG_XIP_KERNEL=y` with `CONFIG_XIP_PHYS_ADDR=0x02000000`
- `CONFIG_SMP=y`, `CONFIG_NR_CPUS=2`
- `CONFIG_FPU=y` (userspace F/D register save/restore)
- `CONFIG_MMU=y` (sv32 page tables)
- `CONFIG_ROMFS_FS=y` for flash-based root filesystem
- `CONFIG_MMC_LITEX=y` for SD card access

## Device tree

`linux/dts/sonata.dts` defines the hardware:

- ISA: `rv32i` base with extensions `a, d, f, i, m, zicsr, zifencei`
- Memory: `0x40000000`, size `0x7EF000` (8 MB minus 68 KB reserved)
- Console: `loglevel=4` (KERN_WARNING and above)
- Root: `/dev/mtdblock0` romfs, read-only

## Known issues

- **CPU1 (second hart)** does not come online on real hardware (works in QEMU).
  Likely requires Verilator simulation to debug.
- **TCC library paths**: the compiled-in library search path only includes
  `/usr/lib`, not `/usr/lib/tcc` or `/lib`. Runtime files must be placed
  directly in `/usr/lib/`.
- **TCC without `-mfpu`**: cannot resolve soft-float symbols (`__adddf3` etc.)
  because TCC does not search `/usr/lib/libgcc.a` automatically. Use `-mfpu`
  when the FPGA bitstream includes FPU support.
- **printf `%e` format**: very small/large floating-point values print as
  `0.000000` due to a musl/TCC interaction. `%f` formatting works correctly.

## Project structure

```
sonata-linux/
├── Makefile                 Top-level build system
├── linux/
│   ├── config/              Kernel config fragments
│   ├── dts/                 Device tree sources (sonata.dts)
│   ├── fpu-stubs/           FPU stub libgcc.a (34 asm wrappers)
│   ├── flasher/             Standalone SD-to-flash programmer
│   ├── xipjump.S            Flash boot trampoline (12 bytes)
│   └── buildroot-ext/       Buildroot external packages (TCC, etc.)
├── tinycc/                  TCC compiler (with -mfpu RV32 extensions)
├── linux-xip/               Kernel source tree (submodule)
├── opensbi-xip/             OpenSBI source tree (submodule)
├── buildroot/               Buildroot cross-toolchain (submodule)
├── litex/                   LiteX SoC framework (submodule)
├── linux-on-litex-vexriscv/ LiteX Linux board integration (submodule)
├── sonata-system/           Sonata FPGA RTL (submodule)
└── out/                     Build outputs
    ├── flashxip.bin          Combined flash image
    ├── rv32.dtb              Device tree blob
    ├── xipjump.bin           Boot trampoline
    ├── boot.json             SD card boot descriptor
    ├── rootfs.romfs          Root filesystem
    └── boot.bin              Standalone flasher
```
