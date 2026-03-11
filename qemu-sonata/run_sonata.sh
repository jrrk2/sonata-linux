#!/bin/bash
# Run the LiteX VexRiscv XIP Linux kernel in QEMU.
#
# Boot flow:
#   1. CPU starts at M-mode stub (0x407FF000 in RAM)
#   2. Stub copies trap handler to SRAM, sets up PMP/delegation, mrets to S-mode
#   3. Kernel boots XIP from flash at 0x02001000 (stub occupies first 4K)
#   4. Shell prompt appears
#
# Usage: ./run_sonata.sh [extra-qemu-args]
#
# Override file paths via environment variables:
#   SDCARD=/path/to/dir ./run_sonata.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU="${SCRIPT_DIR}/build/qemu-system-riscv32"
SDCARD="${SDCARD:-/tmp/sonata-sdcard}"

STUB="${SDCARD}/stub.bin"
DTB="${SDCARD}/rv32.dtb"
FLASHBIN="${SDCARD}/flash.bin"
ROOTFS="${SDCARD}/rootfs.romfs"

# ── Validate ──────────────────────────────────────────────────────────────
if [ ! -x "$QEMU" ]; then
    echo "ERROR: $QEMU not found — run build_qemu_sonata.sh first."
    exit 1
fi

missing=0
for f in "$STUB" "$DTB" "$FLASHBIN" "$ROOTFS"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        missing=1
    fi
done
[ "$missing" -eq 0 ] || exit 1

echo "==> Starting Sonata QEMU simulation"
echo "    stub    : $STUB     → 0x407FF000"
echo "    DTB     : $DTB      → 0x40770000"
echo "    flash   : $FLASHBIN → 0x02000000 (stub+xipImage)"
echo "    rootfs  : $ROOTFS   → 0x02800000"
echo "    Press Ctrl-A X to quit"
echo ""

exec "$QEMU" \
    -machine sonata \
    -nographic \
    -device loader,file="$STUB",addr=0x407FF000,force-raw=on \
    -device loader,file="$DTB",addr=0x40770000,force-raw=on \
    -device loader,file="$FLASHBIN",addr=0x02000000,force-raw=on \
    -device loader,file="$ROOTFS",addr=0x02800000,force-raw=on \
    "$@"
