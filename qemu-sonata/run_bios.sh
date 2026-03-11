#!/bin/bash
# Run the LiteX BIOS + OpenSBI + XIP Linux in QEMU (dual-hart).
#
# Boot flow:
#   1. Both harts reset to ROM (0x00000000) — LiteX BIOS
#   2. Hart 0 runs BIOS main(), hart 1 parks in smp_slave loop
#   3. At BIOS prompt:  boot 0x02780000 0 0x40770000
#      (jumps to OpenSBI, passing hartid=0 and DTB addr in a1)
#   4. OpenSBI starts, wakes hart 1 via HSM, enters kernel
#
# Usage: ./run_bios.sh [extra-qemu-args]
#
# Override file paths via environment variables:
#   SDCARD=/path/to/dir ./run_bios.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU="${SCRIPT_DIR}/build/qemu-system-riscv32"
SDCARD="${SDCARD:-/tmp/sonata-sdcard}"
LITEX="${HOME}/litex-sonata/linux-on-litex-vexriscv/build/sonata"

BIOS="${LITEX}/software/bios/bios.bin"
DTB="${SDCARD}/rv32.dtb"
FLASHBIN="${SDCARD}/flashxip.bin"

# ── Validate ──────────────────────────────────────────────────────────────
if [ ! -x "$QEMU" ]; then
    echo "ERROR: $QEMU not found — run build_qemu_sonata.sh first."
    exit 1
fi

missing=0
for f in "$BIOS" "$DTB" "$FLASHBIN"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        missing=1
    fi
done
[ "$missing" -eq 0 ] || exit 1

echo "==> Starting Sonata QEMU (BIOS boot, 2 harts)"
echo "    BIOS    : $BIOS     → 0x00000000 (ROM)"
echo "    DTB     : $DTB      → 0x40770000 (RAM)"
echo "    flash   : $FLASHBIN → 0x02000000 (kernel+opensbi+rootfs)"
echo "    Press Ctrl-A X to quit"
echo ""
echo "    At BIOS prompt, type:"
echo "      boot 0x02780000 0 0x40770000"
echo ""

exec "$QEMU" \
    -machine sonata \
    -smp 2 \
    -m 32M \
    -nographic \
    -device loader,file="$BIOS",addr=0x00000000,force-raw=on \
    -device loader,file="$DTB",addr=0x40770000,force-raw=on \
    -device loader,file="$FLASHBIN",addr=0x02000000,force-raw=on \
    "$@"
