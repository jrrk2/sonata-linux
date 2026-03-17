../qemu-sonata/build/qemu-system-riscv32-unsigned \
  -machine sonata -m 32M -nographic \
  -drive file=swap.img,format=raw,id=swap -device virtio-blk-device,drive=swap \
  -device loader,file=../out/xipjump.bin,addr=0x407FF000,force-raw=on \
  -device loader,file=../out/rv32.dtb,addr=0x40770000,force-raw=on \
  -device loader,file=../out/flashxip.bin,addr=0x02000000,force-raw=on
