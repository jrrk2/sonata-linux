# Makefile for Sonata flash programmer
#
# Builds a bare-metal binary that reads flashxip.bin from SD card
# and programs it into SPI NOR flash.
#
# Usage: make  (from this directory, or invoked by top-level Makefile)

TOP       ?= $(abspath ../..)
CROSS     ?= $(TOP)/buildroot/output/host/bin/riscv32-buildroot-linux-musl-

CC        := $(CROSS)gcc
OBJCOPY   := $(CROSS)objcopy

# FatFs sources from LiteX
FATFS_DIR := $(TOP)/litex/litex/soc/software/libfatfs

CFLAGS    := -march=rv32ima_zicsr_zifencei -mabi=ilp32 \
             -nostdlib -nostartfiles -ffreestanding -fno-stack-protector \
             -fno-pic -fno-pie \
             -Os -Wall -Wno-unused-function -Wno-unused-but-set-variable \
             -I$(FATFS_DIR)

LDFLAGS   := -T linker.ld -nostdlib -nostartfiles -static -no-pie

OBJS      := crt0.o main.o ff.o ffunicode.o

OUT       ?= $(TOP)/out

.PHONY: all clean

all: $(OUT)/boot.bin
	@echo "=== boot.bin ready: $$(stat -c%s $< 2>/dev/null || stat -f%z $<) bytes ==="

$(OUT)/boot.bin: flasher.elf | $(OUT)
	$(OBJCOPY) -O binary $< $@

$(OUT):
	mkdir -p $(OUT)

flasher.elf: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

crt0.o: crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

ff.o: $(FATFS_DIR)/ff.c
	$(CC) $(CFLAGS) -c -o $@ $<

ffunicode.o: $(FATFS_DIR)/ffunicode.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f *.o flasher.elf $(OUT)/boot.bin
