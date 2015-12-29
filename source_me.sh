
export ROOT=$(pwd)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH=$PATH:$ROOT/tools/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu/bin:$ROOT/tools/bin

gdb_attach() {
  aarch64-linux-gnu-gdb --command=./.gdb.cmd
}

rebuild_kernel() {
  pushd build/kernel
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || return
    cp arch/arm64/boot/Image $ROOT/root/
    cp vmlinux $ROOT/root/
    cp System.map $ROOT/root/
    aarch64-linux-gnu-objdump -d vmlinux > $ROOT/root/dis.s
  popd
}

run() {
 qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $ROOT/root/Image \
	-initrd $ROOT/root/root.cpio \
	-nographic $*
}
