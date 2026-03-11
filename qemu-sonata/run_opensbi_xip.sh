#!/bin/bash
# Run OpenSBI XIP boot in QEMU Sonata.
#
# Boot flow:
#   1. CPU starts at OpenSBI (0x02780000 in flash)
#   2. OpenSBI inits, jumps to kernel at 0x02000000 in S-mode
#   3. Kernel boots XIP from flash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU="${SCRIPT_DIR}/build/qemu-system-riscv32"
SDCARD="${SDCARD:-/tmp/sonata-sdcard}"

KERNEL="${SDCARD}/xipImage"
OPENSBI="/home/jonathan/opensbi-xip/build/platform/litex/vexriscv/firmware/fw_jump.bin"
DTB="/home/jonathan/opensbi-xip/sonata-xip.dtb"
ROOTFS="${SDCARD}/rootfs.romfs"

missing=0
for f in "$KERNEL" "$OPENSBI" "$DTB" "$ROOTFS"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        missing=1
    fi
done
[ "$missing" -eq 0 ] || exit 1

echo "==> Starting Sonata QEMU (OpenSBI XIP)"
echo "    kernel  : $KERNEL  → 0x02000000"
echo "    opensbi : $OPENSBI → 0x02780000"
echo "    DTB     : $DTB     → 0x40770000"
echo "    rootfs  : $ROOTFS  → 0x02800000"
echo "    Press Ctrl-A X to quit"
echo ""

exec "$QEMU" \
    -machine sonata \
    -nographic \
    -device loader,file="$KERNEL",addr=0x02000000,force-raw=on \
    -device loader,file="$OPENSBI",addr=0x02780000,force-raw=on \
    -device loader,file="$DTB",addr=0x40770000,force-raw=on \
    -device loader,file="$ROOTFS",addr=0x02800000,force-raw=on \
    -device loader,addr=0x02780000,cpu-num=0 \
    "$@"
