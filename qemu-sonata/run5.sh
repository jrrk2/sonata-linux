../qemu-sonata/build/qemu-system-riscv32-unsigned \
  -machine sonata -m 32M -nographic \
  -device loader,file=../sonata-linux/out/flashxip.bin,addr=0x02000000,force-raw=on
