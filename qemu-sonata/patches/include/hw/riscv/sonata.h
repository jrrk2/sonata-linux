/*
 * QEMU RISC-V Board compatible with LiteX VexRiscv on lowRISC Sonata FPGA
 *
 * Copyright (c) 2024 lowRISC contributors
 *
 * Models the LiteX VexRiscv SoC as instantiated on the Sonata FPGA board,
 * closely enough to boot a CONFIG_XIP_KERNEL Linux kernel:
 *
 *   0x02000000  Flash (XIP)   32 MB  (kernel + rootfs, memory-mapped)
 *   0x40000000  HyperRAM       8 MB  (kernel .data/.bss, page tables, etc.)
 *   0xf0001000  LiteUART       256 B (LiteX UART, console)
 *   0xf0010000  CLINT         64 KB  (timer + software interrupts)
 *   0xf0c00000  PLIC           4 MB  (SiFive PLIC, 32 sources)
 *   0x10000000  SRAM           6 KB  (M-mode trap handler, invisible to kernel)
 *
 * The CPU is a VexRiscv (RV32IMA, sv32 MMU), modelled here with the
 * generic QEMU "rv32" type.  A minimal M-mode stub loads at 0x407FF000,
 * copies its trap handler to SRAM, then mrets to the XIP kernel at 0x02000000.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2 or later, as published by the Free Software Foundation.
 */

#ifndef HW_RISCV_SONATA_H
#define HW_RISCV_SONATA_H

#include "hw/riscv/riscv_hart.h"
#include "hw/sysbus.h"
#include "chardev/char-fe.h"
#include "qom/object.h"

/* ── LiteUART (LiteX UART) device ──────────────────────────────────────── */

#define TYPE_LITEX_LITEUART "litex-liteuart"
OBJECT_DECLARE_SIMPLE_TYPE(LitexLiteUARTState, LITEX_LITEUART)

struct LitexLiteUARTState {
    SysBusDevice parent_obj;

    MemoryRegion iomem;
    CharBackend  chr;
    qemu_irq     irq;

    uint8_t  rx_fifo[64];
    uint32_t rx_head;
    uint32_t rx_tail;
    uint32_t rx_count;

    uint32_t ev_pending;
    uint32_t ev_enable;
};

/* ── Memory map ────────────────────────────────────────────────────────── */

typedef enum {
    SONATA_DEV_FLASH,       /* XIP flash:       0x02000000, 32 MB  */
    SONATA_DEV_HYPERRAM,    /* HyperRAM:        0x40000000,  8 MB  */
    SONATA_DEV_UART0,       /* LiteUART:        0xf0001000, 256 B  */
    SONATA_DEV_CLINT,       /* CLINT (ACLINT):  0xf0010000, 64 KB  */
    SONATA_DEV_PLIC,        /* SiFive PLIC:     0xf0c00000,  4 MB  */
    SONATA_DEV_SOC_CTRL,    /* LiteX SoC ctrl:  0xf0000000, 256 B  */
    SONATA_DEV_SRAM,        /* SRAM:            0x10000000,  6 KB  */
    SONATA_DEV_SWITCHES,    /* Switches CSR:    0xf0004800, 256 B  */
} SonataDevices;

static const hwaddr sonata_memmap[][2] = {
    /*                              base          size   */
    [SONATA_DEV_FLASH]    = { 0x02000000,  0x2000000 }, /*  32 MB */
    [SONATA_DEV_HYPERRAM] = { 0x40000000,   0x800000 }, /*   8 MB */
    [SONATA_DEV_UART0]    = { 0xf0001000,      0x100 }, /* 256  B */
    [SONATA_DEV_CLINT]    = { 0xf0010000,    0x10000 }, /*  64 KB */
    [SONATA_DEV_PLIC]     = { 0xf0c00000,   0x400000 }, /*   4 MB */
    [SONATA_DEV_SOC_CTRL] = { 0xf0000000,      0x100 }, /* 256  B */
    [SONATA_DEV_SRAM]     = { 0x10000000,     0x1800 }, /*   6 KB */
    [SONATA_DEV_SWITCHES] = { 0xf0004800,      0x100 }, /* 256  B */
};

/* PLIC parameters (match sonata.dts) */
#define SONATA_PLIC_NUM_SOURCES      32
#define SONATA_PLIC_NUM_PRIORITIES    7
#define SONATA_PLIC_PRIORITY_BASE    0x000000
#define SONATA_PLIC_PENDING_BASE     0x001000
#define SONATA_PLIC_ENABLE_BASE      0x002000
#define SONATA_PLIC_ENABLE_STRIDE       0x80
#define SONATA_PLIC_CONTEXT_BASE     0x200000
#define SONATA_PLIC_CONTEXT_STRIDE    0x1000

/* PLIC IRQ assignments (match sonata.dts) */
#define SONATA_UART0_IRQ              1

/* System / timebase clock frequency (50 MHz, matches DTS) */
#define SONATA_SYSCLK_FREQ   50000000UL

/* M-mode stub load address in HyperRAM (temporary, kernel reclaims) */
#define SONATA_STUB_ADDR     0x407FF000UL

/* ── Machine and SoC type names ────────────────────────────────────────── */

#define TYPE_SONATA_MACHINE    MACHINE_TYPE_NAME("sonata")
#define TYPE_SONATA_SOC        "riscv.litex.sonata.soc"

typedef struct SonataSoCState {
    DeviceState parent_obj;

    RISCVHartArrayState cpus;
    LitexLiteUARTState  uart0;
    MemoryRegion        flash;
    MemoryRegion        sram;

    DeviceState        *plic;

    MemoryRegion        soc_ctrl_iomem;
    uint32_t            soc_ctrl_scratch;

    MemoryRegion        switches_iomem;
    uint32_t            switches_in;    /* raw pin value (active-low) */
} SonataSoCState;

DECLARE_INSTANCE_CHECKER(SonataSoCState, SONATA_SOC, TYPE_SONATA_SOC)

typedef struct SonataState {
    MachineState parent_obj;
    SonataSoCState soc;
} SonataState;

DECLARE_INSTANCE_CHECKER(SonataState, SONATA_MACHINE, TYPE_SONATA_MACHINE)

#endif /* HW_RISCV_SONATA_H */
