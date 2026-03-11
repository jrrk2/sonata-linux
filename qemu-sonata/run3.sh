build/qemu-system-riscv32-unsigned -machine sonata -m 32M -nographic \
  -device loader,file=../sonata-linux/linux-xip/arch/riscv/boot/xipImage,addr=0x02000000,force-raw=on \
  -device loader,file=../sonata-linux/out/opensbi-xip.bin,addr=0x02540000,force-raw=on \
  -device loader,file=../sonata-linux/out/rootfs.romfs,addr=0x02800000,force-raw=on \
  -device loader,file=../sonata-linux/out/rv32.dtb,addr=0x40770000,force-raw=on \
  -device loader,file=../sonata-linux/out/xipjump.bin,addr=0x407FF000,force-raw=on 
