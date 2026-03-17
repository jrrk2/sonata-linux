#!/bin/bash
# Build a customised QEMU 8.2.2 with the lowRISC Sonata machine.
# Run from ~/qemu-sonata/.  Produces build/qemu-system-riscv32.
set -euo pipefail

QEMU_TAG="v8.2.2"
QEMU_DIR="$(pwd)/qemu-src"
BUILD_DIR="$(pwd)/build"
PATCH_DIR="$(pwd)/patches"

# ── 1. Fetch source ─────────────────────────────────────────────────────────
if [ ! -d "$QEMU_DIR" ]; then
    echo "==> Cloning QEMU $QEMU_TAG (shallow, riscv32 only) …"
    git clone --depth 1 --branch "$QEMU_TAG" \
        https://gitlab.com/qemu-project/qemu.git "$QEMU_DIR"
    # Pull in just the submodules we actually need
    cd "$QEMU_DIR"
    git submodule update --init --depth 1 \
        ui/keycodemapdb \
        tests/fp/berkeley-softfloat-3 \
        tests/fp/berkeley-testfloat-3 \
        dtc
    cd -
else
    echo "==> QEMU source already present at $QEMU_DIR, skipping clone."
fi

# ── 2. Apply Sonata machine files ────────────────────────────────────────────
echo "==> Applying Sonata machine files …"

cp -v "$PATCH_DIR/hw/riscv/sonata.c" \
      "$QEMU_DIR/hw/riscv/sonata.c"

cp -v "$PATCH_DIR/include/hw/riscv/sonata.h" \
      "$QEMU_DIR/include/hw/riscv/sonata.h"

# Remove any existing SONATA config block from Kconfig, then add new one
sed -i '/^config SONATA$/,/^$/d' "$QEMU_DIR/hw/riscv/Kconfig"
if ! grep -q "config SONATA" "$QEMU_DIR/hw/riscv/Kconfig"; then
    sed -i 's/^# RISC-V machines in alphabetical order/config SONATA\n    bool\n    select RISCV_ACLINT\n    select SIFIVE_PLIC\n    select UNIMP\n    select VIRTIO_MMIO\n\n# RISC-V machines in alphabetical order/' \
        "$QEMU_DIR/hw/riscv/Kconfig"
    echo "  Updated hw/riscv/Kconfig"
fi

# Enable CONFIG_SONATA in the riscv32 default device config
DEVCONFIG="$QEMU_DIR/configs/devices/riscv32-softmmu/default.mak"
if ! grep -q "CONFIG_SONATA" "$DEVCONFIG"; then
    echo "CONFIG_SONATA=y" >> "$DEVCONFIG"
    echo "  Updated $DEVCONFIG"
fi

# Add sonata.c build entry to hw/riscv/meson.build if not already present
if ! grep -q "sonata.c" "$QEMU_DIR/hw/riscv/meson.build"; then
    sed -i "s|riscv_ss.add(files('riscv_hart.c'))|riscv_ss.add(files('riscv_hart.c'))\nriscv_ss.add(when: 'CONFIG_SONATA', if_true: files('sonata.c'))|" \
        "$QEMU_DIR/hw/riscv/meson.build"
    echo "  Updated hw/riscv/meson.build"
fi

# ── 3. Configure ─────────────────────────────────────────────────────────────
echo "==> Configuring (riscv32-softmmu only) …"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
"$QEMU_DIR/configure" \
    --target-list=riscv32-softmmu \
    --disable-werror \
    --disable-docs \
    --disable-gtk \
    --disable-sdl \
    --disable-vnc \
    --disable-opengl \
    --disable-virglrenderer \
    --disable-spice \
    --disable-usb-redir \
    --disable-smartcard \
    --disable-libnfs \
    --disable-libiscsi \
    --disable-curl \
    --disable-capstone \
    --prefix="$(pwd)/install"

# ── 4. Build ─────────────────────────────────────────────────────────────────
echo "==> Building …"
make -j"$(nproc)"

echo ""
echo "==> Done.  Binary: $BUILD_DIR/qemu-system-riscv32"
echo ""
echo "Run with:  ./run_sonata.sh"
