# sonata-linux — Top-level build for Linux on Sonata FPGA
#
# Submodules:
#   sonata-system/            FPGA RTL (CHERIoT Ibex)
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

# Config and source (local — no longer from sonata-system submodule)
CONFIG_DIR   := $(TOP)/linux/config
DTS_DIR      := $(TOP)/linux/dts
SDCARD_SRC   := $(TOP)/linux/sdcard
BR2_EXT      := $(TOP)/linux/buildroot-ext

# Output
OUT          := $(TOP)/out
SDCARD_OUT   ?= /tmp/sonata-sdcard

# macOS: prepend GNU coreutils wrappers to PATH (created by make setup)
export PATH := $(TOP)/.host-tools:$(PATH)

# macOS: host compiler flags for kernel/OpenSBI host tools
#   -std=gnu17          GCC 15 defaults to C23 which breaks old code
#   -B.host-tools/      use ld wrapper that strips ELF-only flags
#   -I host/include     elf.h, byteswap.h shims
#   -include compat.h   uuid_t conflict workaround
HOSTCC_MACOS := $(shell which gcc) -std=gnu17 \
	-B$(TOP)/.host-tools/ \
	-I$(BR_OUTPUT)/host/include \
	-include $(BR_OUTPUT)/host/include/macos-compat.h

# ── OpenSBI ───────────────────────────────────────────────────────────

OPENSBI_PLATFORM := litex/vexriscv
OPENSBI_FW_JUMP  := $(OPENSBI_SRC)/build/platform/$(OPENSBI_PLATFORM)/firmware/fw_jump.bin

# ── Flash layout ──────────────────────────────────────────────────────

OPENSBI_OFFSET := 0x600000
DTB_OFFSET     := 0x6FF000
ROOTFS_OFFSET  := 0x700000

# ── Output files ──────────────────────────────────────────────────────

XIPIMAGE     := $(LINUX_SRC)/arch/riscv/boot/xipImage
BR_TARGET    := $(BR_OUTPUT)/target
ROOTFS_ROMFS := $(OUT)/rootfs.romfs
ROOTFS       := $(ROOTFS_ROMFS)

.PHONY: all setup setup-buildroot setup-kernel setup-opensbi \
        kernel opensbi dtb flashxip sdcard bitstream rootfs uf2 \
        flash-info flasher clean kernel-clean opensbi-clean help

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
	@echo "  make flasher         Build standalone SD→flash programmer (out/boot.bin)"
	@echo "  make flash-info      Show BIOS commands for hardware flashing"
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
	@# macOS fixes for buildroot
	@# 1. /bin/true doesn't exist (SIP makes /bin read-only)
	sed -i.bak 's|/bin/true|/usr/bin/true|g' \
		$(BUILDROOT)/package/autoconf/autoconf.mk \
		$(BUILDROOT)/package/pkg-autotools.mk
	@# 2. program_invocation_short_name is glibc-only
	@grep -q '__APPLE__' $(BUILDROOT)/toolchain/toolchain-wrapper.c || \
		perl -i.bak -0pe \
		's{(#include <stdbool.h>)}{$$1\n\n#ifdef __APPLE__\nstatic const char *_get_progname(void) { return getprogname(); }\n#define program_invocation_short_name _get_progname()\n#endif}' \
		$(BUILDROOT)/toolchain/toolchain-wrapper.c
	@# 3. Apple ld doesn't support -s or --hash-style (ELF-only flags)
	sed -i.bak 's/-s -Wl,--hash-style=[^ ]*//' \
		$(BUILDROOT)/toolchain/toolchain-wrapper.mk
	@# 4. GCC 15 defaults to C23 where () means (void) — old code needs gnu17
	@#    Set via HOSTCC so it applies even when packages override CFLAGS
	@# 5. GNU coreutils + ld wrapper for macOS
	@mkdir -p $(TOP)/.host-tools
	@ln -sf $$(which gsed)      $(TOP)/.host-tools/sed
	@ln -sf $$(which gcp)       $(TOP)/.host-tools/cp
	@ln -sf $$(which gdate)     $(TOP)/.host-tools/date
	@ln -sf $$(which gstat)     $(TOP)/.host-tools/stat
	@ln -sf $$(which gmktemp)   $(TOP)/.host-tools/mktemp
	@ln -sf $$(which greadlink) $(TOP)/.host-tools/readlink
	@ln -sf $$(which gfind)     $(TOP)/.host-tools/find
	@# ld wrapper: strip ELF-only flags (--version-script, --hash-style)
	@test -x $(TOP)/.host-tools/ld || { \
		printf '#!/bin/bash\nargs=()\nfor arg in "$$@"; do\n  case "$$arg" in\n    --version-script=*|--hash-style=*) ;;\n    *) args+=("$$arg") ;;\n  esac\ndone\nexec /opt/local/bin/ld "$${args[@]}"\n' \
			> $(TOP)/.host-tools/ld && chmod +x $(TOP)/.host-tools/ld; }
	@# 6. host-kmod is not needed (CONFIG_MODULES=n) but linux
	@#    unconditionally depends on it; remove from both Config.in and linux.mk
	@#    to avoid building kmod (which has Linux-only deps: byteswap.h, etc.)
	sed -i.bak '/select BR2_PACKAGE_HOST_KMOD/d' \
		$(BUILDROOT)/linux/Config.in
	sed -i.bak '/host-kmod/d' \
		$(BUILDROOT)/linux/linux.mk
	@# 7. macOS lacks <elf.h> and <byteswap.h> — provide shims
	@mkdir -p $(BR_OUTPUT)/host/include
	@cp -n $(BR_OUTPUT)/host/riscv32-buildroot-linux-musl/sysroot/usr/include/elf.h \
		$(BR_OUTPUT)/host/include/elf.h 2>/dev/null || true
	@test -f $(BR_OUTPUT)/host/include/byteswap.h || \
		printf '#ifndef _BYTESWAP_H\n#define _BYTESWAP_H\n#include <stdint.h>\nstatic inline uint16_t __bswap_16(uint16_t x){return x<<8|x>>8;}\nstatic inline uint32_t __bswap_32(uint32_t x){return x>>24|(x>>8&0xff00)|(x<<8&0xff0000)|x<<24;}\nstatic inline uint64_t __bswap_64(uint64_t x){return((__bswap_32(x)+0ULL)<<32)|__bswap_32(x>>32);}\n#define bswap_16(x) __bswap_16(x)\n#define bswap_32(x) __bswap_32(x)\n#define bswap_64(x) __bswap_64(x)\n#endif\n' \
			> $(BR_OUTPUT)/host/include/byteswap.h
	@# 8. macOS uuid_t (unsigned char[16]) conflicts with kernel's uuid_t (struct)
	@#    Pre-include macOS headers then redirect uuid_t to avoid collision
	@test -f $(BR_OUTPUT)/host/include/macos-compat.h || \
		printf '#ifdef __APPLE__\n#include <unistd.h>\n#define uuid_t __kernel_uuid_t\n#endif\n' \
			> $(BR_OUTPUT)/host/include/macos-compat.h
	cd $(BUILDROOT) && \
		$(MAKE) BR2_EXTERNAL="$(LITEX_LINUX)/buildroot:$(BR2_EXT)" sonata_defconfig && \
		PATH="$(TOP)/.host-tools:$$PATH" \
		$(MAKE) HOSTCC="$$(which gcc) -std=gnu17 -B$(TOP)/.host-tools/ -include $(BR_OUTPUT)/host/include/macos-compat.h" -j$$(nproc)
	@echo "=== Buildroot complete ==="
	@echo "Toolchain: $(CROSS)gcc"
	@echo "Target dir: $(BR_TARGET)"

setup-kernel:
	@echo "=== Kernel tree is a git submodule (linux-xip/) ==="
	@test -d $(LINUX_SRC)/arch/riscv || { echo "ERROR: run 'git submodule update --init linux-xip'"; exit 1; }
	@echo "Run 'make rootfs' to generate rootfs.romfs from buildroot target"

setup-opensbi:
	@echo "=== OpenSBI tree is a git submodule (opensbi-xip/) ==="
	@test -d $(OPENSBI_SRC)/lib || { echo "ERROR: run 'git submodule update --init opensbi-xip'"; exit 1; }

# ── Kernel ────────────────────────────────────────────────────────────

kernel: $(XIPIMAGE)

$(XIPIMAGE): $(CONFIG_DIR)/xip-additions.config $(DTS_DIR)/sonata.dts | $(OUT)
	@echo "=== Building xipImage ==="
	@test -d $(LINUX_SRC)/arch/riscv || { echo "ERROR: run 'git submodule update --init linux-xip'"; exit 1; }
	@# Update built-in DTB from checked-in DTS
	dtc -I dts -O dtb -o $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb $(DTS_DIR)/sonata.dts 2>/dev/null
	base64 $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb > $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb.b64
	@# Configure from tinyconfig + XIP additions
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) HOSTCC="$(HOSTCC_MACOS)" tinyconfig && \
		scripts/kconfig/merge_config.sh -m .config $(CONFIG_DIR)/xip-additions.config && \
		scripts/config --set-val CONFIG_MISC_FILESYSTEMS y && \
		scripts/config --set-val CONFIG_MTD_ROM y && \
		scripts/config --disable CONFIG_BUILTIN_DTB && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) HOSTCC="$(HOSTCC_MACOS)" olddefconfig
	@# Verify critical options
	@grep -q 'CONFIG_XIP_KERNEL=y' $(LINUX_SRC)/.config || \
		{ echo "ERROR: XIP_KERNEL lost after olddefconfig!"; exit 1; }
	@# Build
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) HOSTCC="$(HOSTCC_MACOS)" -j$$(nproc) xipImage modules
	@echo "=== xipImage + modules ready ==="

# ── OpenSBI ───────────────────────────────────────────────────────────

opensbi: $(OUT)/opensbi-xip.bin

$(OPENSBI_FW_JUMP): $(OUT)/rv32.dtb
	@echo "=== Building OpenSBI fw_jump ==="
	@test -d $(OPENSBI_SRC)/lib || { echo "ERROR: run 'git submodule update --init opensbi-xip'"; exit 1; }
	cd $(OPENSBI_SRC) && \
		$(MAKE) CROSS_COMPILE=$(CROSS) PLATFORM=$(OPENSBI_PLATFORM) \
			PLATFORM_RISCV_XLEN=32 \
			FW_TEXT_START=0x02600000 \
			FW_RW_ADDR=0x407F0000 \
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

# ── Trampoline: copy DTB from flash to RAM, jump to OpenSBI ──────────

$(OUT)/xipjump.bin: linux/xipjump.S | $(OUT)
	$(CROSS)gcc -c -march=rv32ima -mabi=ilp32 -o $(OUT)/xipjump.o $<
	$(CROSS)ld -Ttext=0 -o $(OUT)/xipjump.elf $(OUT)/xipjump.o
	$(CROSS)objcopy -O binary $(OUT)/xipjump.elf $@

# ── Boot JSON ─────────────────────────────────────────────────────────

$(OUT)/boot.json: | $(OUT)
	printf '{\n    "xipjump.bin": "0x40000000"\n}\n' > $@

# ── Rootfs ────────────────────────────────────────────────────────────

rootfs: $(ROOTFS_ROMFS)

$(ROOTFS_ROMFS): | $(OUT)
	@echo "=== Generating rootfs.romfs from buildroot target ==="
	@test -d $(BR_TARGET) || { echo "ERROR: run 'make setup-buildroot' first"; exit 1; }
	@# Install kernel modules into rootfs
	mkdir -p $(BR_TARGET)/lib/modules
	find $(LINUX_SRC) -name '*.ko' -exec cp {} $(BR_TARGET)/lib/modules/ \;
	@echo "--- Kernel modules ---"
	@ls $(BR_TARGET)/lib/modules/*.ko 2>/dev/null || echo "  (none)"
	genromfs -d $(BR_TARGET) -f $@ -V rootfs
	@echo "=== rootfs.romfs ready: $$(du -h $@ | cut -f1) ==="

# ── Flash image ───────────────────────────────────────────────────────

$(OUT)/flashxip.bin: $(XIPIMAGE) $(OUT)/opensbi-xip.bin $(OUT)/rv32.dtb $(ROOTFS_ROMFS) | $(OUT)
	@echo "=== Assembling flashxip.bin ==="
	@test -n "$(ROOTFS)" -a -f "$(ROOTFS)" || \
		{ echo "ERROR: rootfs.romfs not found. Place it in $(OUT)/rootfs.romfs"; exit 1; }
	cp $(XIPIMAGE) $@
	@KSIZE=$$(wc -c < $(XIPIMAGE) | tr -d ' '); \
	if [ $$KSIZE -gt $$(($(OPENSBI_OFFSET))) ]; then \
		echo "ERROR: xipImage ($$KSIZE bytes) exceeds OpenSBI slot ($$(($(OPENSBI_OFFSET))) bytes)"; \
		rm -f $@; exit 1; \
	fi
	truncate -s $$(($(OPENSBI_OFFSET))) $@
	cat $(OUT)/opensbi-xip.bin >> $@
	truncate -s $$(($(DTB_OFFSET))) $@
	@DSIZE=$$(wc -c < $(OUT)/rv32.dtb | tr -d ' '); \
	if [ $$DSIZE -gt 4096 ]; then \
		echo "ERROR: DTB ($$DSIZE bytes) exceeds 4KB sector"; \
		rm -f $@; exit 1; \
	fi
	cat $(OUT)/rv32.dtb >> $@
	truncate -s $$(($(ROOTFS_OFFSET))) $@
	cat $(ROOTFS) >> $@
	@echo "--- Verify ---"
	@hexdump -C -n 16 $@
	@hexdump -C -s $(OPENSBI_OFFSET) -n 16 $@
	@hexdump -C -s $(DTB_OFFSET) -n 16 $@
	@hexdump -C -s $(ROOTFS_OFFSET) -n 16 $@
	@ls -la $@

# ── Flash info (BIOS commands for hardware programming) ──────────────

flash-info: $(OUT)/flashxip.bin
	@SIZE=$$(stat -c%s $(OUT)/flashxip.bin); \
	echo ""; \
	echo "=== Flash to hardware ==="; \
	echo "Copy $(OUT)/flashxip.bin to SD card, then in BIOS:"; \
	echo ""; \
	echo "  flash_erase_range 0 $$SIZE"; \
	echo "  flash_from_sdcard flashxip.bin"; \
	echo ""; \
	echo "Image: $(OUT)/flashxip.bin ($$SIZE bytes)"

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
INITRAMFS_LIST  := $(TOP)/linux/initramfs/initramfs.list
STUB_SRC        := $(TOP)/linux/stub/stub.S
STUB_LD         := $(TOP)/linux/stub/stub.ld
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
	@test -d $(LINUX_SRC)/arch/riscv || { echo "ERROR: run 'git submodule update --init linux-xip'"; exit 1; }
	@# Update built-in DTB from RAM boot DTS
	dtc -I dts -O dtb -o $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb $(DTS_DIR)/sonata-ram.dts 2>/dev/null
	base64 $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb > $(LINUX_SRC)/arch/riscv/boot/dts/litex/sonata.dtb.b64
	@# Use saved defconfig if .config is missing
	@test -f $(LINUX_SRC)/.config || \
		cp $(CONFIG_DIR)/ram-defconfig $(LINUX_SRC)/.config
	cd $(LINUX_SRC) && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) HOSTCC="$(HOSTCC_MACOS)" olddefconfig && \
		$(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) HOSTCC="$(HOSTCC_MACOS)" -j$$(nproc) Image
	@echo "=== RAM Image ready: $$(du -h $@ | cut -f1) ==="

$(OUT)/kernel.bin: $(TFTP_STUB) $(RAMIMAGE) | $(OUT)
	@echo "=== Assembling kernel.bin ==="
	@# Stub at offset 0 (4KB), kernel Image at offset 0x1000
	cat $(TFTP_STUB) $(RAMIMAGE) > $@
	@echo "--- Layout (loaded at 0x40200000) ---"
	@echo "  0x000000: M-mode stub (4096 bytes) → 0x40200000 (entry)"
	@echo "  0x001000: kernel Image ($$(stat -c%s $(RAMIMAGE)) bytes) → 0x40201000"
	@echo "  Total: $$(stat -c%s $@) bytes"

# ── Flash programmer (standalone SD→flash tool) ───────────────────

flasher: $(OUT)/boot.bin

$(OUT)/boot.bin: | $(OUT)
	$(MAKE) -C $(TOP)/linux/flasher TOP=$(TOP) CROSS=$(CROSS) OUT=$(OUT)

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	rm -rf $(OUT)

kernel-clean:
	@test -d $(LINUX_SRC) && \
		cd $(LINUX_SRC) && $(MAKE) ARCH=riscv CROSS_COMPILE=$(CROSS) clean || true

opensbi-clean:
	@test -d $(OPENSBI_SRC) && \
		cd $(OPENSBI_SRC) && $(MAKE) CROSS_COMPILE=$(CROSS) PLATFORM=$(OPENSBI_PLATFORM) clean || true
