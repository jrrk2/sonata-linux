/*
 * QEMU RISC-V Board compatible with LiteX VexRiscv on lowRISC Sonata FPGA
 *
 * Copyright (c) 2024 lowRISC contributors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2 or later, as published by the Free Software Foundation.
 */

#include "qemu/osdep.h"
#include "qemu/error-report.h"
#include "qapi/error.h"
#include "hw/boards.h"
#include "hw/loader.h"
#include "hw/sysbus.h"
#include "hw/misc/unimp.h"
#include "hw/riscv/riscv_hart.h"
#include "hw/riscv/boot.h"
#include "hw/riscv/sonata.h"
#include "hw/intc/riscv_aclint.h"
#include "hw/intc/sifive_plic.h"
#include "hw/qdev-properties.h"
#include "hw/qdev-properties-system.h"
#include "chardev/char-fe.h"
#include "hw/irq.h"
#include "sysemu/sysemu.h"
#include "hw/virtio/virtio-mmio.h"
#include "target/riscv/cpu.h"
#include "target/riscv/cpu-qom.h"

/* =========================================================================
 * LiteUART — minimal LiteX UART model (polling mode)
 *
 * Register map (32-bit words, only low 8 bits significant):
 *   0x00  RXTX        Write: TX data   Read: RX data (pops FIFO)
 *   0x04  TXFULL      Read:  TX FIFO full flag (always 0 — instant TX)
 *   0x08  RXEMPTY     Read:  RX FIFO empty flag
 *   0x0C  EV_STATUS   Read:  event status (bit 0 = TX, bit 1 = RX)
 *   0x10  EV_PENDING  R/W1C: event pending
 *   0x14  EV_ENABLE   R/W:   event enable (IRQ mask)
 * ====================================================================== */

#define LITEUART_REG_RXTX        0x00
#define LITEUART_REG_TXFULL      0x04
#define LITEUART_REG_RXEMPTY     0x08
#define LITEUART_REG_EV_STATUS   0x0C
#define LITEUART_REG_EV_PENDING  0x10
#define LITEUART_REG_EV_ENABLE   0x14

#define LITEUART_EV_TX  0x1
#define LITEUART_EV_RX  0x2

static void liteuart_update_irq(LitexLiteUARTState *s)
{
    qemu_set_irq(s->irq, !!(s->ev_pending & s->ev_enable));
}

static uint64_t liteuart_read(void *opaque, hwaddr addr, unsigned size)
{
    LitexLiteUARTState *s = opaque;

    switch (addr) {
    case LITEUART_REG_RXTX:
        if (s->rx_count > 0) {
            uint8_t ch = s->rx_fifo[s->rx_head];
            s->rx_head = (s->rx_head + 1) % ARRAY_SIZE(s->rx_fifo);
            s->rx_count--;
            return ch;
        }
        return 0;

    case LITEUART_REG_TXFULL:
        return 0;   /* TX is never full — writes complete instantly */

    case LITEUART_REG_RXEMPTY:
        return (s->rx_count == 0) ? 1 : 0;

    case LITEUART_REG_EV_STATUS:
        return LITEUART_EV_TX  /* TX always ready */
             | ((s->rx_count > 0) ? LITEUART_EV_RX : 0);

    case LITEUART_REG_EV_PENDING:
        return s->ev_pending;

    case LITEUART_REG_EV_ENABLE:
        return s->ev_enable;

    default:
        return 0;
    }
}

static void liteuart_write(void *opaque, hwaddr addr,
                            uint64_t val, unsigned size)
{
    LitexLiteUARTState *s = opaque;

    switch (addr) {
    case LITEUART_REG_RXTX: {
        /* TX: send byte to chardev backend */
        uint8_t ch = (uint8_t)val;
        qemu_chr_fe_write_all(&s->chr, &ch, 1);
        s->ev_pending |= LITEUART_EV_TX;
        liteuart_update_irq(s);
        break;
    }

    case LITEUART_REG_EV_PENDING:
        /* Write-1-to-clear */
        s->ev_pending &= ~(uint32_t)val;
        liteuart_update_irq(s);
        break;

    case LITEUART_REG_EV_ENABLE:
        s->ev_enable = (uint32_t)val;
        liteuart_update_irq(s);
        break;

    default:
        break;
    }
}

static const MemoryRegionOps liteuart_ops = {
    .read  = liteuart_read,
    .write = liteuart_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .impl  = { .min_access_size = 4, .max_access_size = 4 },
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

/* ── Chardev receive handlers ── */

static int liteuart_can_receive(void *opaque)
{
    LitexLiteUARTState *s = opaque;
    return ARRAY_SIZE(s->rx_fifo) - s->rx_count;
}

static void liteuart_receive(void *opaque, const uint8_t *buf, int size)
{
    LitexLiteUARTState *s = opaque;
    int i;

    for (i = 0; i < size && s->rx_count < ARRAY_SIZE(s->rx_fifo); i++) {
        s->rx_fifo[s->rx_tail] = buf[i];
        s->rx_tail = (s->rx_tail + 1) % ARRAY_SIZE(s->rx_fifo);
        s->rx_count++;
    }

    s->ev_pending |= LITEUART_EV_RX;
    liteuart_update_irq(s);
}

/* ── QOM plumbing ── */

static void liteuart_init(Object *obj)
{
    LitexLiteUARTState *s = LITEX_LITEUART(obj);

    sysbus_init_irq(SYS_BUS_DEVICE(obj), &s->irq);

    memory_region_init_io(&s->iomem, obj, &liteuart_ops, s,
                          "litex-liteuart", 0x100);
    sysbus_init_mmio(SYS_BUS_DEVICE(obj), &s->iomem);
}

static void liteuart_realize(DeviceState *dev, Error **errp)
{
    LitexLiteUARTState *s = LITEX_LITEUART(dev);

    qemu_chr_fe_set_handlers(&s->chr,
                              liteuart_can_receive,
                              liteuart_receive,
                              NULL, NULL, s, NULL, true);
}

static Property liteuart_properties[] = {
    DEFINE_PROP_CHR("chardev", LitexLiteUARTState, chr),
    DEFINE_PROP_END_OF_LIST(),
};

static void liteuart_class_init(ObjectClass *oc, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(oc);
    dc->realize = liteuart_realize;
    device_class_set_props(dc, liteuart_properties);
}

static const TypeInfo liteuart_type_info = {
    .name          = TYPE_LITEX_LITEUART,
    .parent        = TYPE_SYS_BUS_DEVICE,
    .instance_size = sizeof(LitexLiteUARTState),
    .instance_init = liteuart_init,
    .class_init    = liteuart_class_init,
};

/* =========================================================================
 * LiteX SoC Controller — minimal model (reset + scratch register)
 *
 * Register map:
 *   0x00  RESET    Write 1 to reset
 *   0x04  SCRATCH  R/W, initialised to 0x12345678
 * ====================================================================== */

static uint64_t litex_soc_ctrl_read(void *opaque, hwaddr addr, unsigned size)
{
    uint32_t *scratch = opaque;
    switch (addr) {
    case 0x04: return *scratch;
    default:   return 0;
    }
}

static void litex_soc_ctrl_write(void *opaque, hwaddr addr,
                                  uint64_t val, unsigned size)
{
    uint32_t *scratch = opaque;
    switch (addr) {
    case 0x04: *scratch = (uint32_t)val; break;
    default: break;
    }
}

static const MemoryRegionOps litex_soc_ctrl_ops = {
    .read  = litex_soc_ctrl_read,
    .write = litex_soc_ctrl_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .impl  = { .min_access_size = 4, .max_access_size = 4 },
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

/* =========================================================================
 * Switches CSR — LiteX GPIOIn (read-only, active-low)
 *
 * Register map:
 *   0x00  IN          Read: raw pin values (active-low: 0 = switch on)
 *   0x04  MODE        R/W:  ignored (edge/level mode)
 *   0x08  EDGE        R/W:  ignored (edge polarity)
 *   0x0C  EV_STATUS   Read: event status (always 0)
 *   0x10  EV_PENDING  R/W1C: event pending (always 0)
 *   0x14  EV_ENABLE   R/W:  event enable (ignored)
 * ====================================================================== */

static uint64_t litex_switches_read(void *opaque, hwaddr addr, unsigned size)
{
    SonataSoCState *s = opaque;
    switch (addr) {
    case 0x00: return s->switches_in;
    default:   return 0;
    }
}

static void litex_switches_write(void *opaque, hwaddr addr,
                                  uint64_t val, unsigned size)
{
    /* All registers are read-only or ignored */
}

static const MemoryRegionOps litex_switches_ops = {
    .read  = litex_switches_read,
    .write = litex_switches_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .impl  = { .min_access_size = 4, .max_access_size = 4 },
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

/* =========================================================================
 * SoC
 * ====================================================================== */

static void sonata_soc_init(Object *obj)
{
    SonataSoCState *s = SONATA_SOC(obj);

    object_initialize_child(obj, "cpus",  &s->cpus,  TYPE_RISCV_HART_ARRAY);
    object_initialize_child(obj, "uart0", &s->uart0, TYPE_LITEX_LITEUART);
}

static void sonata_soc_realize(DeviceState *dev_soc, Error **errp)
{
    SonataSoCState *s       = SONATA_SOC(dev_soc);
    MachineState   *ms      = MACHINE(qdev_get_machine());
    MemoryRegion   *sys_mem = get_system_memory();

    /* ── CPU: generic rv32 with sv32 MMU, reset at stub in RAM ────── */
    object_property_set_str(OBJECT(&s->cpus), "cpu-type", ms->cpu_type,
                            &error_abort);
    object_property_set_int(OBJECT(&s->cpus), "num-harts", 1, &error_abort);
    object_property_set_int(OBJECT(&s->cpus), "resetvec",
                            SONATA_STUB_ADDR, &error_abort);
    sysbus_realize(SYS_BUS_DEVICE(&s->cpus), &error_fatal);

    /* ── Flash (32 MB at 0x02000000) ───────────────────────────────
     * Modelled as RAM so the generic loader can write xipImage + rootfs
     * into it.  The CPU then executes XIP from this region.            */
    memory_region_init_ram(&s->flash, OBJECT(dev_soc),
                           "sonata.flash",
                           sonata_memmap[SONATA_DEV_FLASH][1],
                           &error_fatal);
    memory_region_add_subregion(sys_mem,
                                sonata_memmap[SONATA_DEV_FLASH][0],
                                &s->flash);

    /* ── SRAM (6 KB at 0x10000000) ─────────────────────────────────
     * M-mode trap handler lives here.  Invisible to the Linux kernel
     * (not in the DTS memory node).                                  */
    memory_region_init_ram(&s->sram, OBJECT(dev_soc),
                           "sonata.sram",
                           sonata_memmap[SONATA_DEV_SRAM][1],
                           &error_fatal);
    memory_region_add_subregion(sys_mem,
                                sonata_memmap[SONATA_DEV_SRAM][0],
                                &s->sram);

    /* ── PLIC (SiFive-compatible, 32 sources, M+S mode contexts) ── */
    s->plic = sifive_plic_create(
        sonata_memmap[SONATA_DEV_PLIC][0],
        (char *)"MS",              /* one hart, M-mode + S-mode contexts */
        1,                         /* num_harts                          */
        0,                         /* hartid_base                        */
        SONATA_PLIC_NUM_SOURCES,
        SONATA_PLIC_NUM_PRIORITIES,
        SONATA_PLIC_PRIORITY_BASE,
        SONATA_PLIC_PENDING_BASE,
        SONATA_PLIC_ENABLE_BASE,
        SONATA_PLIC_ENABLE_STRIDE,
        SONATA_PLIC_CONTEXT_BASE,
        SONATA_PLIC_CONTEXT_STRIDE,
        sonata_memmap[SONATA_DEV_PLIC][1]);

    /* ── CLINT / ACLINT (at 0xf0010000) ──────────────────────────── */
    riscv_aclint_swi_create(
        sonata_memmap[SONATA_DEV_CLINT][0],
        0, 1, false);

    riscv_aclint_mtimer_create(
        sonata_memmap[SONATA_DEV_CLINT][0] + RISCV_ACLINT_SWI_SIZE,
        RISCV_ACLINT_DEFAULT_MTIMER_SIZE,
        0, 1,
        RISCV_ACLINT_DEFAULT_MTIMECMP,
        RISCV_ACLINT_DEFAULT_MTIME,
        SONATA_SYSCLK_FREQ,
        false);

    /* ── LiteUART (at 0xf0001000, IRQ 1) ─────────────────────────── */
    qdev_prop_set_chr(DEVICE(&s->uart0), "chardev", serial_hd(0));

    if (!sysbus_realize(SYS_BUS_DEVICE(&s->uart0), errp)) {
        return;
    }
    sysbus_mmio_map(SYS_BUS_DEVICE(&s->uart0), 0,
                    sonata_memmap[SONATA_DEV_UART0][0]);
    sysbus_connect_irq(SYS_BUS_DEVICE(&s->uart0), 0,
                       qdev_get_gpio_in(s->plic, SONATA_UART0_IRQ));

    /* ── LiteX SoC Controller (scratch register at 0xf0000004) ──── */
    s->soc_ctrl_scratch = 0x12345678;
    memory_region_init_io(&s->soc_ctrl_iomem, OBJECT(dev_soc),
                          &litex_soc_ctrl_ops, &s->soc_ctrl_scratch,
                          "litex-soc-ctrl",
                          sonata_memmap[SONATA_DEV_SOC_CTRL][1]);
    memory_region_add_subregion(sys_mem,
                                sonata_memmap[SONATA_DEV_SOC_CTRL][0],
                                &s->soc_ctrl_iomem);

    /* ── Switches CSR (at 0xf0004800) ────────────────────────────── */
    memory_region_init_io(&s->switches_iomem, OBJECT(dev_soc),
                          &litex_switches_ops, s,
                          "litex-switches",
                          sonata_memmap[SONATA_DEV_SWITCHES][1]);
    memory_region_add_subregion(sys_mem,
                                sonata_memmap[SONATA_DEV_SWITCHES][0],
                                &s->switches_iomem);

    create_unimplemented_device("sonata.mmc",     0xf0003000, 0x200);
    create_unimplemented_device("sonata.leds",    0xf0002800, 0x100);
    create_unimplemented_device("sonata.spi-eth", 0x80302000, 0x2000);

    /* ── virtio-mmio transports (for swap, block devices, etc.) ──── */
    for (int i = 0; i < SONATA_VIRTIO_COUNT; i++) {
        hwaddr addr = sonata_memmap[SONATA_DEV_VIRTIO][0]
                      + i * sonata_memmap[SONATA_DEV_VIRTIO][1];
        int irq = SONATA_VIRTIO_IRQ_BASE + i;

        sysbus_create_simple("virtio-mmio", addr,
                             qdev_get_gpio_in(s->plic, irq));
    }
}

static void sonata_soc_class_init(ObjectClass *oc, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(oc);
    dc->realize       = sonata_soc_realize;
    dc->user_creatable = false;
}

static const TypeInfo sonata_soc_type = {
    .name          = TYPE_SONATA_SOC,
    .parent        = TYPE_DEVICE,
    .instance_size = sizeof(SonataSoCState),
    .instance_init = sonata_soc_init,
    .class_init    = sonata_soc_class_init,
};

/* =========================================================================
 * Machine
 * ====================================================================== */

static void sonata_machine_init(MachineState *machine)
{
    SonataState  *s       = SONATA_MACHINE(machine);
    MemoryRegion *sys_mem = get_system_memory();

    /* Realise the SoC (creates CPU, flash, UART, CLINT, PLIC) */
    object_initialize_child(OBJECT(machine), "soc", &s->soc, TYPE_SONATA_SOC);
    qdev_realize(DEVICE(&s->soc), NULL, &error_fatal);

    /* HyperRAM (8 MB at 0x40000000) — the kernel's writable data region.
     * QEMU allocates this via default_ram_id / default_ram_size. */
    memory_region_add_subregion(sys_mem,
                                sonata_memmap[SONATA_DEV_HYPERRAM][0],
                                machine->ram);

    /*
     * All file loading is done externally via -device loader on the
     * command line.  The run script places:
     *   stub.bin     → 0x407FF000  (RAM, temporary)
     *   rv32.dtb     → 0x40770000  (RAM)
     *   xipImage     → 0x02000000  (flash)
     *   rootfs.romfs → 0x02300000  (flash)
     *
     * The CPU resetvec is set to SONATA_STUB_ADDR (0x407FF000) so
     * execution begins at the M-mode stub, which sets up trap handling
     * in SRAM, then mrets to the kernel in S-mode.
     */

    /* Set switches value — default 0x7 (all high = all off, active-low) */
    s->soc.switches_in = 0x7;
    if (machine->kernel_cmdline && machine->kernel_cmdline[0]) {
        /* Abuse kernel_cmdline to pass selsw value, e.g. -append "selsw=6" */
        const char *p = strstr(machine->kernel_cmdline, "selsw=");
        if (p) {
            s->soc.switches_in = (uint32_t)strtoul(p + 6, NULL, 0) & 0x7;
        }
    }
}

static void sonata_machine_class_init(ObjectClass *oc, void *data)
{
    MachineClass *mc = MACHINE_CLASS(oc);

    mc->desc             = "lowRISC Sonata FPGA — LiteX VexRiscv XIP Linux";
    mc->init             = sonata_machine_init;
    mc->max_cpus         = 1;
    mc->default_cpu_type = TYPE_RISCV_CPU_BASE32;
    mc->default_ram_id   = "sonata.hyperram";
    mc->default_ram_size = sonata_memmap[SONATA_DEV_HYPERRAM][1]; /* 8 MB */
}

static const TypeInfo sonata_machine_type = {
    .name          = TYPE_SONATA_MACHINE,
    .parent        = TYPE_MACHINE,
    .instance_size = sizeof(SonataState),
    .class_init    = sonata_machine_class_init,
};

/* =========================================================================
 * Type registration
 * ====================================================================== */

static void sonata_register_types(void)
{
    type_register_static(&liteuart_type_info);
    type_register_static(&sonata_soc_type);
    type_register_static(&sonata_machine_type);
}

type_init(sonata_register_types)
