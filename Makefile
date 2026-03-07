# sonata-linux — Top-level build for Linux on Sonata FPGA
#
# Submodules:
#   sonata-system/            FPGA RTL, DTS, kernel config, boot scripts
#   linux-on-litex-vexriscv/  LiteX Linux orchestrator (boards.py, patches)
#   litex/, litex-boards/     LiteX SoC framework + board definitions
#   migen/                    Migen HDL (LiteX dependency)
#   litespi/, litesdcard/     SPI flash + SD card controllers
#   litedram/                 DRAM controller (HyperRAM)
#   pythondata-cpu-vexriscv-smp/  VexRiscv SMP CPU verilog
#   pythondata-software-*/    Picolibc + compiler-rt (BIOS dependencies)
#   buildroot/                Cross toolchain + rootfs + kernel source
#
# Usage:
#   make setup      First-time: build buildroot toolchain, extract kernel+opensbi
#   make            Build all flash + SD card binaries
#   make bitstream  Build FPGA bitstream (requires Vivado)
#   make sdcard     Populate SD card directory
#   make clean      Remove build artifacts
#
# Prerequisites:
#   - Xilinx Vivado 2022.2+ (for bitstream only)
#   - dtc (device-tree-compiler)
#   - Standard build tools (gcc, make, etc.)

SHELL := /bin/bash

# ── Paths ──────────────────────────────────────────────────────────────

TOP          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Submodule paths
SONATA       := $(TOP)/sonata-system
LITEX_LINUX  := $(TOP)/linux-on-litex-vexriscv
LITEX        := $(TOP)/litex
LITEX_BOARDS := $(TOP)/litex-boards
MIGEN        := $(TOP)/migen
LITESPI      := $(TOP)/litespi
LITESDCARD   := $(TOP)/litesdcard
LITEDRAM     := $(TOP)/litedram
BUILDROOT    := $(TOP)/buildroot
VEXRISCV_SMP := $(TOP)/pythondata-cpu-vexriscv-smp

# Build trees (created by setup)
LINUX_SRC    := $(TOP)/linux-xip
OPENSBI_SRC  := $(TOP)/opensbi-xip

# Buildroot output — 'make setup' builds buildroot using the buildroot submodule
# with the linux-on-litex-vexriscv overlay (patches, configs).
BR_OUTPUT    := $(BUILDROOT)/output
CROSS        := $(BR_OUTPUT)/host/bin/riscv32-buildroot-linux-musl-

# Config and source from sonata-system
CONFIG_DIR   := $(SONATA)/linux/config
DTS_DIR      := $(SONATA)/linux/dts
DRIVERS_DIR  := $(SONATA)/linux/drivers
PATCHES_DIR  := $(SONATA)/linux/patches
SDCARD_SRC   := $(SONATA)/linux/sdcard

# Output
OUT          := $(TOP)/out
SDCARD_OUT   ?= /tmp/sonata-sdcard

# ── OpenSBI ───────────────────────────────────────────────────────────

OPENSBI_PLATFORM := litex/vexriscv
OPENSBI_FW_JUMP  := $(OPENSBI_SRC)/build/platform/$(OPENSBI_PLATFORM)/firmware/fw_jump.bin

# ── Flash layout ──────────────────────────────────────────────────────

OPENSBI_OFFSET := 0x540000
ROOTFS_OFFSET  := 0x5C0000

# ── Output files ──────────────────────────────────────────────────────

XIPIMAGE     := $(LINUX_SRC)/arch/riscv/boot/xipImage
BR_TARGET    := $(BR_OUTPUT)/target
ROOTFS_ROMFS := $(OUT)/rootfs.romfs
ROOTFS       := $(ROOTFS_ROMFS)

.PHONY: all setup setup-buildroot setup-kernel setup-opensbi \
        kernel opensbi dtb flashxip sdcard bitstream rootfs uf2 \
        clean kernel-clean opensbi-clean help

all: $(OUT)/flashxip.bin $(OUT)/rv32.dtb $(OUT)/xipjump.bin $(OUT)/boot.json
	@echo ""
	@echo "=== Build complete ==="
	@ls -la $(OUT)/flashxip.bin $(OUT)/rv32.dtb $(OUT)/xipjump.bin $(OUT)/boot.json

help:
	@echo "sonata-linux build system"
	@echo ""
	@echo "First-time setup:"
	@echo "  make setup           Build toolchain, extract kernel+opensbi trees"
	@echo ""
	@echo "Build targets:"
	@echo "  make                 Build flashxip.bin + SD card boot files"
	@echo "  make rootfs          Generate rootfs.romfs from buildroot target"
	@echo "  make bitstream       Build FPGA bitstream (requires Vivado)"
	@echo "  make sdcard          Copy all files to $(SDCARD_OUT)"
	@echo "  make kernel          Rebuild just the kernel"
	@echo "  make opensbi         Rebuild just OpenSBI"
	@echo "  make dtb             Rebuild just the DTB"
	@echo ""
	@echo "Clean:"
	@echo "  make clean           Remove out/ directory"
	@echo "  make kernel-clean    Clean kernel build tree"
	@echo "  make opensbi-clean   Clean OpenSBI build tree"

# ── Directory creation ────────────────────────────────────────────────

$(OUT):
	mkdir -p $(OUT)

# ── First-time setup ─────────────────────────────────────────────────

setup: setup-buildroot setup-kernel setup-opensbi
	@echo ""
	@echo "=== Setup complete ==="
	@echo "Cross compiler: $(CROSS)gcc"
	@echo "Kernel tree:    $(LINUX_SRC)"
	@echo "OpenSBI tree:   $(OPENSBI_SRC)"
	@echo ""
	@echo "Now run: make"

setup-buildroot:
	@echo "=== Building buildroot (toolchain + kernel + rootfs) ==="
	cd $(BUILDROOT) && \
		$(MAKE) BR2_EXTERNAL=$(LITEX_LINUX)/buildroot litex_vexriscv_defconfig && \
		$(MAKE) -j$$(nproc)
	@echo "=== Buildroot complete ==="
	@echo "Toolchain: $(CROSS)gcc"
	@echo "Target dir: $(BR_TARGET)"

setup-kernel:
	@echo "=== Setting up kernel tree ==="
	@test -d $(BR_OUTPUT)/build/linux-6.9 || { echo "ERROR: run 'make setup-buildroot' first"; exit 1; }
	@if [ ! -d $(LINUX_SRC) ]; then \
		echo "Copying kernel tree to $(LINUX_SRC)..."; \
		cp -a $(BR_OUTPUT)/build/linux-6.9 $(LINUX_SRC); \
		echo "Kernel tree ready."; \
	else \
		echo "$(LINUX_SRC) already exists, skipping."; \
	fi
	@echo "Run 'make rootfs' to generate rootfs.romfs from buildroot target"

setup-opensbi:
	@echo "=== Setting up OpenSBI tree ==="
	@test -d $(BR_OUTPUT)/build/opensbi-1.3.1-linux-on-litex-vexriscv || { echo "ERROR: run 'make setup-buildroot' first"; exit 1; }
	@if [ ! -d $(OPENSBI_SRC) ]; then \
		echo "Copying OpenSBI tree to $(OPENSBI_SRC)..."; \
		cp -a $(BR_OUTPUT)/build/opensbi-1.3.1-linux-on-litex-vexriscv $(OPENSBI_SRC); \
		echo "OpenSBI tree ready."; \
	else \
		echo "$(OPENSBI_SRC) already exists, skipping."; \
	fi

# ── Kernel ────────────────────────────────────────────────────────────

kernel: $(XIPIMAGE)

$(XIPIMAGE): $(CONFIG_DIR)/xip-additions.config $(DTS_DIR)/sonata.dts | $(OUT)
	@echo "=== Building xipImage ==="
	@test -d $(LINUX_SRC) || { echo "ERROR: run 'make setup' first"; exit 1; }
	@# Update built-in DTB from checked-in DTS
	dtc -I dts -O dtb -o $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb $(DTS_DIR)/sonata.dts 2>/dev/null
	base64 $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb > $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb.b64
	@# Configure from tinyconfig + XIP additions
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) tinyconfig && \
		scripts/kconfig/merge_config.sh -m .config $(CONFIG_DIR)/xip-additions.config && \
		scripts/config --set-val CONFIG_MISC_FILESYSTEMS y && \
		scripts/config --set-val CONFIG_MTD_ROM y && \
		scripts/config --enable CONFIG_BUILTIN_DTB && \
		scripts/config --set-str CONFIG_BUILTIN_DTB_SOURCE "litex/sonata" && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) olddefconfig
	@# Verify critical options
	@grep -q 'CONFIG_XIP_KERNEL=y' $(LINUX_SRC)/.config || \
		{ echo "ERROR: XIP_KERNEL lost after olddefconfig!"; exit 1; }
	@grep -q 'CONFIG_BUILTIN_DTB=y' $(LINUX_SRC)/.config || \
		{ echo "ERROR: BUILTIN_DTB lost after olddefconfig!"; exit 1; }
	@# Build
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) -j$$(nproc) xipImage
	@echo "=== xipImage ready ==="

# ── OpenSBI ───────────────────────────────────────────────────────────

opensbi: $(OUT)/opensbi-xip.bin

$(OPENSBI_FW_JUMP): $(OUT)/rv32.dtb
	@echo "=== Building OpenSBI fw_jump ==="
	@test -d $(OPENSBI_SRC) || { echo "ERROR: run 'make setup' first"; exit 1; }
	cd $(OPENSBI_SRC) && \
		$(MAKE) CROSS_COMPILE=$(CROSS) PLATFORM=$(OPENSBI_PLATFORM) \
			PLATFORM_RISCV_XLEN=32 \
			FW_TEXT_START=0x02540000 \
			FW_RW_ADDR=0x407F8000 \
			FW_JUMP_ADDR=0x02000000 \
			FW_JUMP_FDT_ADDR=0x40770000 \
			FW_FDT_PATH=$(OUT)/rv32.dtb \
			-j$$(nproc)

$(OUT)/opensbi-xip.bin: $(OPENSBI_FW_JUMP) | $(OUT)
	cp $< $@

# ── Device Tree ───────────────────────────────────────────────────────

dtb: $(OUT)/rv32.dtb

$(OUT)/rv32.dtb: $(DTS_DIR)/sonata.dts | $(OUT)
	dtc -I dts -O dtb -o $@ $< 2>/dev/null

# ── Trampoline: lui a1,0x40770; lui t0,0x02780; jr t0 ────────────────

$(OUT)/xipjump.bin: | $(OUT)
	printf '\xb7\x05\x77\x40\xb7\x02\x54\x02\x67\x80\x02\x00' > $@

# ── Boot JSON ─────────────────────────────────────────────────────────

$(OUT)/boot.json: | $(OUT)
	printf '{\n    "rv32.dtb":    "0x40770000",\n    "xipjump.bin": "0x40000000"\n}\n' > $@

# ── Rootfs ────────────────────────────────────────────────────────────

rootfs: $(ROOTFS_ROMFS)

$(ROOTFS_ROMFS): | $(OUT)
	@echo "=== Generating rootfs.romfs from buildroot target ==="
	@test -d $(BR_TARGET) || { echo "ERROR: run 'make setup-buildroot' first"; exit 1; }
	genromfs -d $(BR_TARGET) -f $@ -V rootfs
	@echo "=== rootfs.romfs ready: $$(du -h $@ | cut -f1) ==="

# ── Flash image ───────────────────────────────────────────────────────

$(OUT)/flashxip.bin: $(XIPIMAGE) $(OUT)/opensbi-xip.bin $(ROOTFS_ROMFS) | $(OUT)
	@echo "=== Assembling flashxip.bin ==="
	@test -n "$(ROOTFS)" -a -f "$(ROOTFS)" || \
		{ echo "ERROR: rootfs.romfs not found. Place it in $(OUT)/rootfs.romfs"; exit 1; }
	cp $(XIPIMAGE) $@
	truncate -s $$(($(OPENSBI_OFFSET))) $@
	cat $(OUT)/opensbi-xip.bin >> $@
	truncate -s $$(($(ROOTFS_OFFSET))) $@
	cat $(ROOTFS) >> $@
	@echo "--- Verify ---"
	@hexdump -C $@ | head -1
	@hexdump -C $@ -s $(OPENSBI_OFFSET) -n 8
	@hexdump -C $@ -s $(ROOTFS_OFFSET) -n 8
	@ls -la $@

# ── FPGA bitstream ────────────────────────────────────────────────────

bitstream:
	@echo "=== Building FPGA bitstream ==="
	@test -f /opt/Xilinx/Vivado/2022.2/settings64.sh -o -f /home/Xilinx/Vivado/2022.2/settings64.sh || \
		{ echo "ERROR: Vivado 2022.2 not found"; exit 1; }
	@# Remove old GCC 7.2 from PATH to avoid conflicts
	export PATH=$$(echo $$PATH | tr ':' '\n' | grep -v vivado-risc-v | tr '\n' ':' | sed 's/:$$//'); \
	source /home/Xilinx/Vivado/2022.2/settings64.sh 2>/dev/null || source /opt/Xilinx/Vivado/2022.2/settings64.sh; \
	cd $(LITEX_LINUX) && \
		PYTHONPATH=$(LITEX):$(LITEX_BOARDS):$(MIGEN):$(LITESPI):$(LITESDCARD):$(LITEDRAM):$(VEXRISCV_SMP) \
		python3 make.py --board=sonata \
			--cpu-count=1 --with-privileged-debug --jtag-tap --wishbone-force-32b \
			--icache-size=65536 --icache-ways=16 --dcache-size=65536 --dcache-ways=16 \
			--build
	@echo "=== Bitstream ready ==="
	@ls -la $(LITEX_LINUX)/build/sonata/gateware/sonata.bit

# ── UF2 for Sonata USB mass-storage flashing ─────────────────────────
# Slots 1-3 at offsets 0x00000000, 0x10000000, 0x20000000

BITSTREAM    := $(LITEX_LINUX)/build/sonata/gateware/sonata.bit
VERSION      ?= 0.0
UF2_SLOTS    := $(OUT)/sonata-v$(VERSION).bit.slot1.uf2 \
                $(OUT)/sonata-v$(VERSION).bit.slot2.uf2 \
                $(OUT)/sonata-v$(VERSION).bit.slot3.uf2

uf2: $(UF2_SLOTS)

$(OUT)/sonata-v$(VERSION).bit.slot1.uf2: $(BITSTREAM) | $(OUT)
	uf2conv -b 0x00000000 -f 0x6ce29e6b $< -co $@

$(OUT)/sonata-v$(VERSION).bit.slot2.uf2: $(BITSTREAM) | $(OUT)
	uf2conv -b 0x10000000 -f 0x6ce29e6b $< -co $@

$(OUT)/sonata-v$(VERSION).bit.slot3.uf2: $(BITSTREAM) | $(OUT)
	uf2conv -b 0x20000000 -f 0x6ce29e6b $< -co $@

# ── SD card population ────────────────────────────────────────────────

sdcard: all
	mkdir -p $(SDCARD_OUT)
	cp $(OUT)/flashxip.bin $(SDCARD_OUT)/
	cp $(OUT)/rv32.dtb     $(SDCARD_OUT)/
	cp $(OUT)/xipjump.bin  $(SDCARD_OUT)/
	cp $(OUT)/boot.json    $(SDCARD_OUT)/
	@# Copy bitstream if available
	@if [ -f $(LITEX_LINUX)/build/sonata/gateware/sonata.bit ]; then \
		cp $(LITEX_LINUX)/build/sonata/gateware/sonata.bit $(SDCARD_OUT)/sonata.bit; \
		echo "Copied sonata.bit"; \
	fi
	@echo ""
	@echo "=== SD card files in $(SDCARD_OUT) ==="
	@ls -la $(SDCARD_OUT)/

# ── TFTP boot (stub + RAM kernel) ────────────────────────────────────
#
# Builds kernel.bin for TFTP network boot:
#   M-mode stub (4KB) + kernel Image
# Loaded at 0x40200000.  Stub sets up M-mode, mrets into kernel at +0x1000.
# Kernel self-relocates to 0x40000000.  Built-in DTB (no separate DTB needed).
#
# Usage:
#   make tftpboot
#   cp out/kernel.bin /srv/tftp/

RAMIMAGE       := $(LINUX_SRC)/arch/riscv/boot/Image
INITRAMFS_LIST  := $(SONATA)/linux/initramfs/initramfs.list
STUB_SRC        := $(SONATA)/linux/stub/stub.S
STUB_LD         := $(SONATA)/linux/stub/stub.ld
TFTP_STUB       := $(OUT)/tftp-stub.bin

.PHONY: tftpboot ramkernel

TFTP_DIR     ?= /srv/tftp

tftpboot: $(OUT)/kernel.bin
	cp $(OUT)/kernel.bin $(TFTP_DIR)/kernel.bin
	@echo "=== kernel.bin installed to $(TFTP_DIR) ==="
	@ls -la $(TFTP_DIR)/kernel.bin

$(TFTP_STUB): $(STUB_SRC) $(STUB_LD) | $(OUT)
	@echo "=== Building TFTP M-mode stub ==="
	$(CROSS)gcc -nostdlib -nostartfiles -march=rv32ima_zicsr_zifencei -mabi=ilp32 \
		-DTFTP_BOOT -T $(STUB_LD) -o $(OUT)/tftp-stub.elf $(STUB_SRC)
	$(CROSS)objcopy -O binary $(OUT)/tftp-stub.elf $@
	@# Pad to exactly 4KB
	truncate -s 4096 $@
	@echo "  Stub: $$(stat -c%s $@) bytes (padded to 4KB)"

ramkernel: $(RAMIMAGE)

$(RAMIMAGE): $(CONFIG_DIR)/ram-additions.config $(DTS_DIR)/sonata-ram.dts | $(OUT)
	@echo "=== Building RAM kernel Image ==="
	@test -d $(LINUX_SRC) || { echo "ERROR: run 'make setup' first"; exit 1; }
	@# Copy patched drivers into kernel tree
	cp $(DRIVERS_DIR)/spi/spi-opentitan.c $(LINUX_SRC)/drivers/spi/
	cp $(DRIVERS_DIR)/net/ethernet/micrel/ks8851_common.c $(LINUX_SRC)/drivers/net/ethernet/micrel/
	cp $(DRIVERS_DIR)/net/ethernet/micrel/ks8851.h $(LINUX_SRC)/drivers/net/ethernet/micrel/
	cp $(DRIVERS_DIR)/net/ethernet/micrel/ks8851_spi.c $(LINUX_SRC)/drivers/net/ethernet/micrel/
	@# Patch kernel build system for SPI_OPENTITAN (idempotent)
	@grep -q 'SPI_OPENTITAN' $(LINUX_SRC)/drivers/spi/Kconfig || \
		cd $(LINUX_SRC) && patch -p0 < $(PATCHES_DIR)/spi-opentitan-kbuild.patch
	@# Update built-in DTB from RAM boot DTS
	dtc -I dts -O dtb -o $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb $(DTS_DIR)/sonata-ram.dts 2>/dev/null
	base64 $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb > $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb.b64
	@# Configure from tinyconfig + RAM additions
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) tinyconfig && \
		scripts/kconfig/merge_config.sh -m .config $(CONFIG_DIR)/ram-additions.config && \
		scripts/config --disable CONFIG_XIP_KERNEL && \
		scripts/config --disable CONFIG_BLK_DEV_INITRD && \
		scripts/config --enable CONFIG_BUILTIN_DTB && \
		scripts/config --set-str CONFIG_BUILTIN_DTB_SOURCE "litex/sonata" && \
		scripts/config --enable CONFIG_MTD && \
		scripts/config --enable CONFIG_MTD_ROM && \
		scripts/config --enable CONFIG_MTD_BLOCK && \
		scripts/config --enable CONFIG_MTD_PHYSMAP && \
		scripts/config --enable CONFIG_MTD_PHYSMAP_OF && \
		scripts/config --set-val CONFIG_MISC_FILESYSTEMS y && \
		scripts/config --enable CONFIG_ROMFS_FS && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) olddefconfig
	@# Verify critical options
	@grep -q 'CONFIG_BUILTIN_DTB=y' $(LINUX_SRC)/.config || \
		{ echo "ERROR: BUILTIN_DTB lost after olddefconfig!"; exit 1; }
	@if grep -q 'CONFIG_XIP_KERNEL=y' $(LINUX_SRC)/.config; then \
		echo "ERROR: XIP_KERNEL is still enabled!"; exit 1; fi
	@# Build
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) -j$$(nproc) Image
	@echo "=== RAM Image ready: $$(du -h $@ | cut -f1) ==="

$(OUT)/kernel.bin: $(TFTP_STUB) $(RAMIMAGE) | $(OUT)
	@echo "=== Assembling kernel.bin ==="
	@# Stub at offset 0 (4KB), kernel Image at offset 0x1000
	cat $(TFTP_STUB) $(RAMIMAGE) > $@
	@echo "--- Layout (loaded at 0x40200000) ---"
	@echo "  0x000000: M-mode stub (4096 bytes) → 0x40200000 (entry)"
	@echo "  0x001000: kernel Image ($$(stat -c%s $(RAMIMAGE)) bytes) → 0x40201000"
	@echo "  Total: $$(stat -c%s $@) bytes"

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	rm -rf $(OUT)

kernel-clean:
	@test -d $(LINUX_SRC) && \
		cd $(LINUX_SRC) && $(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) clean || true

opensbi-clean:
	@test -d $(OPENSBI_SRC) && \
		cd $(OPENSBI_SRC) && $(MAKE) CROSS_COMPILE=$(CROSS) PLATFORM=$(OPENSBI_PLATFORM) clean || true
