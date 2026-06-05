/*
 * xipjump.S — Flash boot trampoline for Sonata FPGA
 *
 * Loaded to RAM by Sonata BIOS (via boot.json at 0x40000000).
 * Sets a1 to the DTB address in flash and jumps to OpenSBI,
 * which relocates the FDT to RAM (FW_JUMP_FDT_ADDR).
 *
 * Flash layout (base 0x02000000):
 *   +0x000000  xipImage (kernel, XIP)
 *   +0x440000  OpenSBI fw_jump.bin
 *   +0x490000  DTB (8KB slot)
 *   +0x492000  rootfs.romfs
 *
 * Not executed in QEMU (CPU starts directly at OpenSBI).
 */

#define DTB_FLASH   0x02490000  /* 0x02000000 + 0x490000 */
#define OPENSBI     0x02440000  /* 0x02000000 + 0x440000 */

        .section .text
        .globl _start
_start:
        lui     a1, %hi(DTB_FLASH)      /* a1 = FDT in flash */
        lui     t0, %hi(OPENSBI)
        jr      t0
