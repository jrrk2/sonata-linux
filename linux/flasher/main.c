/*
 * Sonata FPGA Flash Programmer
 *
 * Standalone bare-metal program that reads flashxip.bin from a FAT-formatted
 * SD card and programs it into SPI NOR flash.
 *
 * Runs from HyperRAM at 0x40000000 in M-mode.
 * All hardware drivers are self-contained (adapted from LiteX BIOS code).
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>

#include "ff.h"
#include "diskio.h"

/* ═══════════════════════════════════════════════════════════════════════
 * Hardware Constants (from sonata_hw.h)
 * ═══════════════════════════════════════════════════════════════════════ */

#define CLK_FREQ          50000000

/* ── UART ────────────────────────────────────────────────────────────── */

#define UART_BASE         0xf0001000
#define UART_RXTX         (UART_BASE + 0x00)
#define UART_TXFULL       (UART_BASE + 0x04)
#define UART_RXEMPTY      (UART_BASE + 0x08)

/* ── SPI Flash Controller (from generated/csr.h, base 0xf0003800) ──── */

#define SPI_BASE          0xf0003800
#define SPI_PHY_CLK_DIV   (SPI_BASE + 0x00)
#define SPI_MMAP_DUMMY    (SPI_BASE + 0x04)
#define SPI_MASTER_CS     (SPI_BASE + 0x08)
#define SPI_MASTER_PHYCFG (SPI_BASE + 0x0C)
#define SPI_MASTER_RXTX   (SPI_BASE + 0x10)
#define SPI_MASTER_STATUS (SPI_BASE + 0x14)

/* Flash memory-mapped region */
#define FLASH_BASE        0x02000000

/* ── SD Card Controller ──────────────────────────────────────────────── */

#define SD_BASE           0xf0003000
#define SD_PHY_CARD_DET   (SD_BASE + 0x00)
#define SD_PHY_CLK_DIV    (SD_BASE + 0x04)
#define SD_PHY_INIT       (SD_BASE + 0x08)
#define SD_PHY_SETTINGS   (SD_BASE + 0x18)
#define SD_CMD_ARG        (SD_BASE + 0x1C)
#define SD_CMD_CMD        (SD_BASE + 0x20)
#define SD_CMD_SEND       (SD_BASE + 0x24)
#define SD_CMD_RSP0       (SD_BASE + 0x28)
#define SD_CMD_RSP1       (SD_BASE + 0x2C)
#define SD_CMD_RSP2       (SD_BASE + 0x30)
#define SD_CMD_RSP3       (SD_BASE + 0x34)
#define SD_CMD_EVENT      (SD_BASE + 0x38)
#define SD_DATA_EVENT     (SD_BASE + 0x3C)
#define SD_BLK_LENGTH     (SD_BASE + 0x40)
#define SD_BLK_COUNT      (SD_BASE + 0x44)
#define SD_DMA_BASE_HI    (SD_BASE + 0x48)
#define SD_DMA_BASE_LO    (SD_BASE + 0x4C)
#define SD_DMA_LENGTH     (SD_BASE + 0x50)
#define SD_DMA_ENABLE     (SD_BASE + 0x54)
#define SD_DMA_DONE       (SD_BASE + 0x58)

/* ── SD Protocol Constants ───────────────────────────────────────────── */

#define SD_OK             0
#define SD_CRCERROR       1
#define SD_TIMEOUT        2

#define SD_RSP_NONE       0
#define SD_RSP_SHORT      1
#define SD_RSP_LONG       2
#define SD_RSP_SHORT_BUSY 3
#define SD_RSP_CRC        4

#define SD_DATA_XFER_NONE  0
#define SD_DATA_XFER_READ  1
#define SD_DATA_XFER_WRITE 2

#define SD_SWITCH_SWITCH   1
#define SD_GROUP_ACCESSMODE 0
#define SD_SPEED_SDR25     1

#define SD_PHY_1X          0
#define SD_PHY_4X          1

/* ── Flash Constants ─────────────────────────────────────────────────── */

#define SPI_PAGE_SIZE     256
#define SPI_ERASE_SIZE    (64 * 1024)

/* SPI flash commands */
#define CMD_WRITE_ENABLE  0x06
#define CMD_READ_STATUS   0x05
#define CMD_PAGE_PROGRAM  0x12   /* 4-byte address variant */
#define CMD_SECTOR_ERASE  0xDC   /* 4-byte address variant */

/* ═══════════════════════════════════════════════════════════════════════
 * Register I/O
 * ═══════════════════════════════════════════════════════════════════════ */

static inline void reg_write(uint32_t addr, uint32_t val)
{
	*(volatile uint32_t *)(uintptr_t)addr = val;
}

static inline uint32_t reg_read(uint32_t addr)
{
	return *(volatile uint32_t *)(uintptr_t)addr;
}

/* ═══════════════════════════════════════════════════════════════════════
 * UART Driver
 * ═══════════════════════════════════════════════════════════════════════ */

static void uart_putc(char c)
{
	while (reg_read(UART_TXFULL))
		;
	reg_write(UART_RXTX, (uint32_t)c);
}

static void uart_puts(const char *s)
{
	while (*s) {
		if (*s == '\n')
			uart_putc('\r');
		uart_putc(*s++);
	}
}

static void print_hex(uint32_t val, int width)
{
	static const char hex[] = "0123456789abcdef";
	int i;
	int started = 0;

	for (i = 7; i >= 0; i--) {
		int digit = (val >> (i * 4)) & 0xf;
		if (i < width || digit || started || i == 0) {
			uart_putc(hex[digit]);
			started = 1;
		}
	}
}

static void print_dec(uint32_t val)
{
	char buf[10];
	int i = 0;

	if (val == 0) {
		uart_putc('0');
		return;
	}
	while (val) {
		buf[i++] = '0' + (val % 10);
		val /= 10;
	}
	while (i--)
		uart_putc(buf[i]);
}

static void printf(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);

	while (*fmt) {
		if (*fmt != '%') {
			if (*fmt == '\n')
				uart_putc('\r');
			uart_putc(*fmt++);
			continue;
		}
		fmt++;

		/* Parse optional '0' pad and width */
		int pad = ' ';
		int width = 0;
		if (*fmt == '0') {
			pad = '0';
			fmt++;
		}
		while (*fmt >= '0' && *fmt <= '9')
			width = width * 10 + (*fmt++ - '0');

		/* Handle 'l' modifier (ignored, all 32-bit) */
		if (*fmt == 'l')
			fmt++;

		switch (*fmt++) {
		case 'd': {
			int32_t v = va_arg(ap, int32_t);
			if (v < 0) {
				uart_putc('-');
				v = -v;
			}
			print_dec((uint32_t)v);
			break;
		}
		case 'u':
			print_dec(va_arg(ap, uint32_t));
			break;
		case 'x': {
			uint32_t v = va_arg(ap, uint32_t);
			if (width > 0)
				print_hex(v, width);
			else
				print_hex(v, 1);
			break;
		}
		case 's':
			uart_puts(va_arg(ap, const char *));
			break;
		case 'c':
			uart_putc((char)va_arg(ap, int));
			break;
		case '%':
			uart_putc('%');
			break;
		default:
			uart_putc('?');
			break;
		}
	}
	va_end(ap);
}

/* ═══════════════════════════════════════════════════════════════════════
 * Delays
 * ═══════════════════════════════════════════════════════════════════════ */

static void cdelay(int n)
{
	while (n-- > 0)
		asm volatile("");
}

static void busy_wait_us(unsigned int us)
{
	/* ~4 cycles per cdelay iteration at 50MHz */
	cdelay(us * (CLK_FREQ / 1000000 / 4));
}

static void busy_wait(unsigned int ms)
{
	busy_wait_us(ms * 1000);
}

/* ═══════════════════════════════════════════════════════════════════════
 * Cache
 * ═══════════════════════════════════════════════════════════════════════ */

static void flush_dcache(void)
{
	asm volatile(".word 0x500F" ::: "memory");
}

/* ═══════════════════════════════════════════════════════════════════════
 * SPI Flash Driver (adapted from LiteX liblitespi/spiflash.c)
 * ═══════════════════════════════════════════════════════════════════════ */

/*
 * PHY config register layout:
 *   bits [7:0]   = transfer length in bits
 *   bits [11:8]  = bus width (1=single, 2=dual, 4=quad)
 *   bits [23:16] = chip select mask
 */
static void spi_set_config(uint32_t len_bits, uint32_t width, uint32_t mask)
{
	reg_write(SPI_MASTER_PHYCFG,
		  (len_bits & 0xFF) |
		  ((width & 0xF) << 8) |
		  ((mask & 0xFF) << 16));
}

static int spi_transfer_byte(uint8_t b, uint8_t *out)
{
	int timeout;

	/* Wait for TX ready */
	for (timeout = 100000; timeout > 0; timeout--) {
		if (reg_read(SPI_MASTER_STATUS) & 1)
			break;
	}
	if (timeout == 0) {
		printf("SPI: TX not ready (status=0x%08x)\n",
		       reg_read(SPI_MASTER_STATUS));
		return -1;
	}

	reg_write(SPI_MASTER_RXTX, (uint32_t)b);

	/* Wait for RX ready */
	for (timeout = 100000; timeout > 0; timeout--) {
		if (reg_read(SPI_MASTER_STATUS) & 2)
			break;
	}
	if (timeout == 0) {
		printf("SPI: RX not ready (status=0x%08x)\n",
		       reg_read(SPI_MASTER_STATUS));
		return -1;
	}

	*out = (uint8_t)reg_read(SPI_MASTER_RXTX);
	return 0;
}

static int spi_transfer_cmd(const uint8_t *tx, uint8_t *rx, int len)
{
	int i;

	spi_set_config(8, 1, 1);
	reg_write(SPI_MASTER_CS, 1);

	for (i = 0; i < len; i++) {
		if (spi_transfer_byte(tx[i], &rx[i]) < 0) {
			reg_write(SPI_MASTER_CS, 0);
			return -1;
		}
	}

	reg_write(SPI_MASTER_CS, 0);
	return 0;
}

static int spi_write_enable(void)
{
	uint8_t cmd = CMD_WRITE_ENABLE;
	uint8_t dummy;

	return spi_transfer_cmd(&cmd, &dummy, 1);
}

static int spi_read_status(uint32_t *status)
{
	uint8_t tx[4] = { CMD_READ_STATUS, 0, 0, 0 };
	uint8_t rx[4];

	if (spi_transfer_cmd(tx, rx, 4) < 0)
		return -1;
	/* Status is stable in rx[3] (LiteX quirk: need extra clocks) */
	*status = rx[3];
	return 0;
}

static int spi_sector_erase(uint32_t addr)
{
	uint8_t tx[5] = {
		CMD_SECTOR_ERASE,
		(addr >> 24) & 0xFF,
		(addr >> 16) & 0xFF,
		(addr >> 8) & 0xFF,
		addr & 0xFF
	};
	uint8_t rx[5];

	return spi_transfer_cmd(tx, rx, 5);
}

static int spi_page_program(uint32_t addr, const uint8_t *data, int len)
{
	uint8_t dummy;
	int i;

	spi_set_config(8, 1, 1);
	reg_write(SPI_MASTER_CS, 1);

	/* Command + 4-byte address */
	if (spi_transfer_byte(CMD_PAGE_PROGRAM, &dummy) < 0) goto fail;
	if (spi_transfer_byte((addr >> 24) & 0xFF, &dummy) < 0) goto fail;
	if (spi_transfer_byte((addr >> 16) & 0xFF, &dummy) < 0) goto fail;
	if (spi_transfer_byte((addr >> 8) & 0xFF, &dummy) < 0) goto fail;
	if (spi_transfer_byte(addr & 0xFF, &dummy) < 0) goto fail;

	/* Data */
	for (i = 0; i < len; i++) {
		if (spi_transfer_byte(data[i], &dummy) < 0) goto fail;
	}

	reg_write(SPI_MASTER_CS, 0);
	return 0;
fail:
	reg_write(SPI_MASTER_CS, 0);
	return -1;
}

static int spi_erase_range(uint32_t addr, uint32_t len)
{
	uint32_t i, j, status;
	int errors = 0;
	int timeout;

	for (i = 0; i < len; i += SPI_ERASE_SIZE) {
		printf("  Erase 0x%08x", addr + i);

		if (spi_write_enable() < 0) {
			printf(" WREN FAIL\n");
			errors++;
			continue;
		}
		if (spi_sector_erase(addr + i) < 0) {
			printf(" CMD FAIL\n");
			errors++;
			continue;
		}

		/* Poll status with timeout (erase can take up to 3 seconds) */
		for (timeout = 3000; timeout > 0; timeout--) {
			if (spi_read_status(&status) < 0) {
				printf(" STATUS READ FAIL\n");
				errors++;
				break;
			}
			if (!(status & 1))
				break;
			uart_putc('.');
			busy_wait(1);
		}
		if (timeout == 0) {
			printf(" TIMEOUT (status=0x%02x)\n", status);
			errors++;
			continue;
		}
		printf(" OK\n");

		/* Invalidate cache, then verify erased */
		flush_dcache();
		for (j = 0; j < SPI_ERASE_SIZE; j++) {
			uint8_t val = *(volatile uint8_t *)(uintptr_t)(FLASH_BASE + addr + i + j);
			if (val != 0xFF) {
				printf("  ERROR: 0x%08x not erased (0x%02x)\n",
				       addr + i + j, val);
				errors++;
				break;
			}
		}
	}
	return errors;
}

static int spi_write_page(uint32_t addr, const uint8_t *data, int len)
{
	uint32_t status;
	int j, timeout;
	int errors = 0;

	if (spi_write_enable() < 0) {
		printf("  WREN FAIL at 0x%08x\n", addr);
		return 1;
	}
	if (spi_page_program(addr, data, len) < 0) {
		printf("  PROGRAM FAIL at 0x%08x\n", addr);
		return 1;
	}

	/* Wait for write to complete with timeout */
	for (timeout = 100; timeout > 0; timeout--) {
		if (spi_read_status(&status) < 0) {
			printf("  STATUS FAIL at 0x%08x\n", addr);
			return 1;
		}
		if (!(status & 1))
			break;
		busy_wait_us(100);
	}
	if (timeout == 0) {
		printf("  WRITE TIMEOUT at 0x%08x (status=0x%02x)\n", addr, status);
		return 1;
	}

	/* Invalidate cache and verify */
	flush_dcache();
	for (j = 0; j < len; j++) {
		uint8_t val = *(volatile uint8_t *)(uintptr_t)(FLASH_BASE + addr + j);
		if (val != data[j]) {
			printf("  VERIFY FAIL at 0x%08x: got 0x%02x, expected 0x%02x\n",
			       addr + j, val, data[j]);
			errors++;
		}
	}
	return errors;
}

static int spi_write_stream(uint32_t addr, const uint8_t *data, uint32_t len)
{
	uint32_t offset = 0;
	int errors = 0;

	while (offset < len) {
		uint32_t page_len = len - offset;
		if (page_len > SPI_PAGE_SIZE)
			page_len = SPI_PAGE_SIZE;
		errors += spi_write_page(addr + offset, data + offset, page_len);
		offset += page_len;
	}
	return errors;
}

/* ═══════════════════════════════════════════════════════════════════════
 * SD Card Driver (adapted from LiteX liblitesdcard/sdcard.c)
 * ═══════════════════════════════════════════════════════════════════════ */

static int sd_wait_cmd_done(void)
{
	uint32_t event;

	for (;;) {
		event = reg_read(SD_CMD_EVENT);
		if (event & 0x1)
			break;
		busy_wait_us(10);
	}
	if (event & 0x4)
		return SD_TIMEOUT;
	if (event & 0x8)
		return SD_CRCERROR;
	return SD_OK;
}

static int sd_wait_data_done(void)
{
	uint32_t event;

	for (;;) {
		event = reg_read(SD_DATA_EVENT);
		if (event & 0x1)
			break;
		busy_wait_us(10);
	}
	if (event & 0x4)
		return SD_TIMEOUT;
	if (event & 0x8)
		return SD_CRCERROR;
	return SD_OK;
}

static int sd_send_command(uint32_t arg, uint8_t cmd, uint8_t rsp)
{
	reg_write(SD_CMD_ARG, arg);
	reg_write(SD_CMD_CMD, ((uint32_t)cmd << 8) | rsp);
	reg_write(SD_CMD_SEND, 1);
	return sd_wait_cmd_done();
}

static void sd_set_clk_freq(unsigned long clk_freq)
{
	uint32_t divider;

	if (clk_freq == 0)
		divider = 256;
	else {
		divider = (CLK_FREQ + clk_freq - 1) / clk_freq;
		if (divider < 2) divider = 2;
		if (divider > 256) divider = 256;
	}
	reg_write(SD_PHY_CLK_DIV, divider);
}

static void sd_dma_setup(void *buf, uint32_t len)
{
	reg_write(SD_DMA_ENABLE, 0);
	reg_write(SD_DMA_BASE_HI, 0);           /* high 32 bits (always 0 on RV32) */
	reg_write(SD_DMA_BASE_LO, (uint32_t)(uintptr_t)buf);
	reg_write(SD_DMA_LENGTH, len);
	reg_write(SD_DMA_ENABLE, 1);
}

static void sd_dma_wait(void)
{
	while (!(reg_read(SD_DMA_DONE) & 1))
		;
}

static int sd_init(void)
{
	uint16_t rca;
	uint32_t timeout;
	uint32_t r0;
	uint32_t scr_buf[2] __attribute__((aligned(4)));
	uint32_t raw_scr;
	int support_4bit;

	/* Set PHY to 1x speed */
	reg_write(SD_PHY_SETTINGS, SD_PHY_1X);

	/* Set clock to 400KHz for init */
	sd_set_clk_freq(400000);
	busy_wait(1);

	/* Generate 80 dummy clocks + go idle */
	for (timeout = 1000; timeout > 0; timeout--) {
		reg_write(SD_PHY_INIT, 1);
		busy_wait(1);
		if (sd_send_command(0, 0, SD_RSP_NONE) == SD_OK)
			break;
		busy_wait(1);
	}
	if (timeout == 0) {
		printf("CMD0 failed\n");
		return 0;
	}

	/* CMD8: SEND_IF_COND (verify SDHC support) */
	if (sd_send_command(0x1AA, 8, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
		printf("CMD8 failed\n");
		return 0;
	}

	/* Set clock to 25MHz for operation */
	sd_set_clk_freq(25000000);
	busy_wait(1);

	/* ACMD41: APP_SEND_OP_COND (wait for card ready) */
	for (timeout = 1000; timeout > 0; timeout--) {
		sd_send_command(0 << 16, 55, SD_RSP_SHORT | SD_RSP_CRC);
		if (sd_send_command(0x70ff8000, 41, SD_RSP_SHORT) == SD_OK) {
			r0 = reg_read(SD_CMD_RSP0);
			if (r0 & 0x80000000)
				break;
		}
		busy_wait(1);
	}
	if (timeout == 0) {
		printf("ACMD41 failed\n");
		return 0;
	}

	/* CMD2: ALL_SEND_CID */
	if (sd_send_command(0, 2, SD_RSP_LONG | SD_RSP_CRC) != SD_OK) {
		printf("CMD2 failed\n");
		return 0;
	}

	/* CMD3: SET_RELATIVE_ADDRESS */
	if (sd_send_command(0, 3, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
		printf("CMD3 failed\n");
		return 0;
	}
	rca = (reg_read(SD_CMD_RSP0) >> 16) & 0xFFFF;

	/* CMD10: SEND_CID (optional, keeps card happy) */
	if (sd_send_command((uint32_t)rca << 16, 10, SD_RSP_LONG | SD_RSP_CRC) != SD_OK) {
		printf("CMD10 failed\n");
		return 0;
	}

	/* CMD9: SEND_CSD */
	if (sd_send_command((uint32_t)rca << 16, 9, SD_RSP_LONG | SD_RSP_CRC) != SD_OK) {
		printf("CMD9 failed\n");
		return 0;
	}

	/* CMD7: SELECT_CARD */
	if (sd_send_command((uint32_t)rca << 16, 7, SD_RSP_SHORT_BUSY | SD_RSP_CRC) != SD_OK) {
		printf("CMD7 failed\n");
		return 0;
	}

	/* CMD6: SWITCH to SDR25 speed */
	{
		uint32_t arg = (SD_SWITCH_SWITCH << 31) | 0xFFFFFF;
		arg &= ~(0xF << (SD_GROUP_ACCESSMODE * 4));
		arg |= SD_SPEED_SDR25 << (SD_GROUP_ACCESSMODE * 4);

		reg_write(SD_BLK_LENGTH, 64);
		reg_write(SD_BLK_COUNT, 1);
		while (sd_send_command(arg, 6,
			(SD_DATA_XFER_READ << 5) | SD_RSP_SHORT | SD_RSP_CRC) != SD_OK)
			;
		sd_wait_data_done();
	}

	/* ACMD51: SEND_SCR (read SD Configuration Register) */
	sd_dma_setup(scr_buf, 8);

	if (sd_send_command((uint32_t)rca << 16, 55, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
		printf("CMD55 failed\n");
		return 0;
	}
	reg_write(SD_BLK_LENGTH, 8);
	reg_write(SD_BLK_COUNT, 1);
	while (sd_send_command(0, 51,
		(SD_DATA_XFER_READ << 5) | SD_RSP_SHORT | SD_RSP_CRC) != SD_OK)
		;
	sd_wait_data_done();
	sd_dma_wait();
	flush_dcache();

	/* Decode SCR: byte-swap from big-endian DMA data */
	raw_scr = __builtin_bswap32(scr_buf[0]);
	support_4bit = (raw_scr >> 18) & 1;

	if (support_4bit) {
		/* ACMD6: SET_BUS_WIDTH to 4-bit */
		if (sd_send_command((uint32_t)rca << 16, 55, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
			printf("CMD55 failed\n");
			return 0;
		}
		if (sd_send_command(2, 6, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
			printf("ACMD6 failed\n");
			return 0;
		}
		reg_write(SD_PHY_SETTINGS, SD_PHY_4X);
		printf("  4-bit bus enabled\n");
	}

	/* CMD16: SET_BLOCKLEN to 512 */
	if (sd_send_command(512, 16, SD_RSP_SHORT | SD_RSP_CRC) != SD_OK) {
		printf("CMD16 failed\n");
		return 0;
	}

	return 1;
}

static void sd_read(uint32_t block, uint32_t count, uint8_t *buf)
{
	while (count) {
		uint32_t nblocks = count;

		sd_dma_setup(buf, 512 * nblocks);

		if (nblocks > 1) {
			/* CMD18: READ_MULTIPLE_BLOCK */
			reg_write(SD_BLK_LENGTH, 512);
			reg_write(SD_BLK_COUNT, nblocks);
			while (sd_send_command(block, 18,
				(SD_DATA_XFER_READ << 5) | SD_RSP_SHORT | SD_RSP_CRC) != SD_OK)
				;
			sd_wait_data_done();
			/* CMD12: STOP_TRANSMISSION */
			sd_send_command(0, 12, SD_RSP_SHORT_BUSY | SD_RSP_CRC);
		} else {
			/* CMD17: READ_SINGLE_BLOCK */
			reg_write(SD_BLK_LENGTH, 512);
			reg_write(SD_BLK_COUNT, 1);
			while (sd_send_command(block, 17,
				(SD_DATA_XFER_READ << 5) | SD_RSP_SHORT | SD_RSP_CRC) != SD_OK)
				;
			sd_wait_data_done();
		}

		sd_dma_wait();
		block += nblocks;
		buf += 512 * nblocks;
		count -= nblocks;
	}
	flush_dcache();
}

/* ═══════════════════════════════════════════════════════════════════════
 * FatFs Disk I/O Callbacks
 * ═══════════════════════════════════════════════════════════════════════ */

static DSTATUS sd_disk_status_val = STA_NOINIT;

static DSTATUS fatfs_disk_initialize(BYTE drv)
{
	if (drv) return STA_NOINIT;
	if (sd_disk_status_val)
		sd_disk_status_val = sd_init() ? 0 : STA_NOINIT;
	return sd_disk_status_val;
}

static DSTATUS fatfs_disk_status(BYTE drv)
{
	if (drv) return STA_NOINIT;
	return sd_disk_status_val;
}

static DRESULT fatfs_disk_read(BYTE drv, BYTE *buf, LBA_t sector, UINT count)
{
	if (drv) return RES_PARERR;
	sd_read(sector, count, buf);
	return RES_OK;
}

static DISKOPS sd_diskops = {
	.disk_initialize = fatfs_disk_initialize,
	.disk_status     = fatfs_disk_status,
	.disk_read       = fatfs_disk_read,
	.disk_write      = NULL,
	.disk_ioctl      = NULL,
};

/* FfDiskOps is defined in ff.c; we set it at runtime in main() */

/* ═══════════════════════════════════════════════════════════════════════
 * Boot into OpenSBI
 * ═══════════════════════════════════════════════════════════════════════ */

#define OPENSBI_ENTRY    0x02600000   /* OpenSBI entry point in flash (XIP) */
#define DTB_LOAD_ADDR    0x40770000
#define DTB_FLASH_OFFSET 0x6FF000     /* DTB sector in flash image */

static void __attribute__((noreturn)) boot_opensbi(void)
{
	uint32_t dtb_addr = FLASH_BASE + DTB_FLASH_OFFSET;

	printf("Jumping to OpenSBI at 0x%08x (dtb=0x%08x in flash)\n\n",
	       OPENSBI_ENTRY, dtb_addr);

	/*
	 * Jump to OpenSBI in flash.  Flush caches first: dcache may
	 * hold stale flash reads, icache may hold pre-programming
	 * instructions.  OpenSBI's startup copies .data from flash
	 * LMA to RAM VMA before using any writable data.
	 */
	flush_dcache();
	asm volatile(
		"fence.i\n"        /* flush icache */
		"mv a0, zero\n"    /* hartid = 0 */
		"mv a1, %0\n"      /* a1 = dtb address (in flash) */
		"jr %1\n"
		:: "r"(dtb_addr), "r"(OPENSBI_ENTRY)
		: "a0", "a1"
	);

	__builtin_unreachable();
}

/* ═══════════════════════════════════════════════════════════════════════
 * Main
 * ═══════════════════════════════════════════════════════════════════════ */

/* 4KB read buffer */
static uint8_t chunk_buf[4096] __attribute__((aligned(4)));

/* Per-sector dirty flags (64KB sectors; 512 covers up to 32MB) */
#define MAX_SECTORS 512
static uint8_t dirty[MAX_SECTORS];

/*
 * Scan flash against file, marking which 64KB sectors differ.
 * Returns number of dirty sectors, or -1 on read error.
 * Rewinds the file when done.
 */
static int scan_sectors(FIL *fil, uint32_t fsize, int *nsectors_out)
{
	uint32_t offset = 0;
	int n_dirty = 0;
	int nsectors = (fsize + SPI_ERASE_SIZE - 1) / SPI_ERASE_SIZE;
	volatile uint8_t *flash = (volatile uint8_t *)FLASH_BASE;
	UINT bytes_read;
	FRESULT fr;
	int i;

	*nsectors_out = nsectors;
	for (i = 0; i < nsectors; i++)
		dirty[i] = 0;

	flush_dcache();
	printf("Comparing flash with flashxip.bin...\n");

	while (offset < fsize) {
		uint32_t chunk = fsize - offset;
		uint32_t j;
		int sector = offset / SPI_ERASE_SIZE;

		if (chunk > sizeof(chunk_buf))
			chunk = sizeof(chunk_buf);

		fr = f_read(fil, chunk_buf, chunk, &bytes_read);
		if (fr != FR_OK || bytes_read == 0) {
			printf("  Read error at offset 0x%08x (error %d)\n",
			       offset, fr);
			f_lseek(fil, 0);
			return -1;
		}

		if (!dirty[sector]) {
			for (j = 0; j < bytes_read; j++) {
				if (flash[offset + j] != chunk_buf[j]) {
					dirty[sector] = 1;
					n_dirty++;
					break;
				}
			}
		}

		offset += bytes_read;

		/* Progress every 256KB */
		if ((offset % (256 * 1024)) == 0 || offset >= fsize) {
			printf("  Scanned %u / %u bytes (%u%%)\n",
			       offset, fsize, (offset * 100) / fsize);
		}
	}

	f_lseek(fil, 0);
	return n_dirty;
}

int main(void)
{
	FATFS fs;
	FIL fil;
	FRESULT fr;
	uint32_t fsize;
	UINT bytes_read;
	int errors;

	uart_puts("\n");
	uart_puts("================================\n");
	uart_puts(" Sonata Flash Programmer\n");
	uart_puts("================================\n");
	uart_puts("\n");

	/* Read SPI flash ID to verify communication */
	{
		uint8_t tx[4] = { 0x9F, 0, 0, 0 };
		uint8_t rx[4];
		printf("SPI flash: clk_div=%u, probing...\n",
		       reg_read(SPI_PHY_CLK_DIV));
		if (spi_transfer_cmd(tx, rx, 4) < 0) {
			printf("FATAL: SPI flash not responding!\n");
			return 1;
		}
		printf("SPI flash ID: %02x %02x %02x\n",
		       rx[1], rx[2], rx[3]);
	}

	/* Set up FatFs disk operations */
	FfDiskOps = &sd_diskops;

	/*
	 * SD card is already initialized by the BIOS (which loaded us from it).
	 * Just mark it ready and set block length to be safe.
	 */
	printf("SD card: using BIOS-initialized state\n");
	sd_send_command(512, 16, SD_RSP_SHORT | SD_RSP_CRC);  /* CMD16: SET_BLOCKLEN */
	sd_disk_status_val = 0;

	/* Mount FAT filesystem */
	fr = f_mount(&fs, "", 1);
	if (fr != FR_OK) {
		printf("FATAL: f_mount failed (error %d)\n", fr);
		return 1;
	}
	printf("FAT filesystem mounted\n");

	/* Open flashxip.bin */
	fr = f_open(&fil, "flashxip.bin", FA_READ);
	if (fr != FR_OK) {
		printf("FATAL: Cannot open flashxip.bin (error %d)\n", fr);
		return 1;
	}

	fsize = f_size(&fil);
	printf("flashxip.bin: %u bytes\n\n", fsize);

	if (fsize == 0) {
		printf("FATAL: File is empty!\n");
		return 1;
	}

	/* Scan sectors to find which ones differ */
	{
		int nsectors, n_dirty, i;

		n_dirty = scan_sectors(&fil, fsize, &nsectors);
		if (n_dirty == 0) {
			printf("Flash is up to date (%d sectors verified)\n",
			       nsectors);
			f_close(&fil);
			f_mount(NULL, "", 0);
			boot_opensbi();
		}
		if (n_dirty < 0) {
			printf("Read error during scan — programming all sectors\n");
			for (i = 0; i < nsectors; i++)
				dirty[i] = 1;
			n_dirty = nsectors;
		}

		printf("%d / %d sectors need updating", n_dirty, nsectors);
		if (n_dirty <= 8) {
			printf(":");
			for (i = 0; i < nsectors; i++)
				if (dirty[i])
					printf(" %d", i);
		}
		printf("\n\n");
	}

	/* Erase and program only dirty sectors */
	errors = 0;
	{
		int nsectors = (fsize + SPI_ERASE_SIZE - 1) / SPI_ERASE_SIZE;
		int s, done = 0, total_dirty = 0;

		for (s = 0; s < nsectors; s++)
			if (dirty[s])
				total_dirty++;

		for (s = 0; s < nsectors; s++) {
			uint32_t sect_addr = (uint32_t)s * SPI_ERASE_SIZE;
			uint32_t sect_end, pos;

			if (!dirty[s])
				continue;

			done++;
			printf("[%d/%d] Sector %d (0x%08x)\n",
			       done, total_dirty, s, sect_addr);

			/* Erase */
			errors += spi_erase_range(sect_addr, SPI_ERASE_SIZE);

			/* Program: seek to sector start in file, write pages */
			sect_end = sect_addr + SPI_ERASE_SIZE;
			if (sect_end > fsize)
				sect_end = fsize;

			fr = f_lseek(&fil, sect_addr);
			if (fr != FR_OK) {
				printf("  Seek error (error %d)\n", fr);
				errors++;
				continue;
			}

			for (pos = sect_addr; pos < sect_end; ) {
				uint32_t chunk = sect_end - pos;
				if (chunk > sizeof(chunk_buf))
					chunk = sizeof(chunk_buf);

				fr = f_read(&fil, chunk_buf, chunk, &bytes_read);
				if (fr != FR_OK || bytes_read == 0) {
					printf("  Read error at 0x%08x (error %d)\n",
					       pos, fr);
					errors++;
					break;
				}

				errors += spi_write_stream(pos, chunk_buf, bytes_read);
				pos += bytes_read;
			}
		}
	}

	f_close(&fil);
	f_mount(NULL, "", 0);

	printf("\n");
	if (errors) {
		printf("DONE with %d errors!\n", errors);
	} else {
		printf("SUCCESS: flash updated and verified\n");
		boot_opensbi();
	}

	printf("\nHalted.\n");
	for (;;)
		asm volatile("wfi");
}
