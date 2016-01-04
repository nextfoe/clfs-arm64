
export TOPDIR=$(pwd)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH=$PATH:$TOPDIR/tools/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu/bin:$TOPDIR/tools/bin

gdb_attach() {
  aarch64-linux-gnu-gdb --command=./.gdb.cmd
}

rebuild_kernel() {
  pushd build/kernel
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || return
    cp arch/arm64/boot/Image $TOPDIR/target/
    cp vmlinux $TOPDIR/target/
    cp System.map $TOPDIR/target/
    aarch64-linux-gnu-objdump -d vmlinux > $TOPDIR/target/dis.s
  popd
}

do_update() {
  pushd $1
  git fetch --all || return
  git rebase origin/master || return
  popd
}


run() {
 qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $TOPDIR/target/Image \
	-initrd $TOPDIR/target/rootfs.cpio \
	-nographic $*
}

mkfs() {
  if [ ! -f $TOPDIR/disk.img ]; then
    sudo dd if=/dev/zero of=disk.img bs=4k count=10240
    echo -e 'n\np\n1\n\n\np\nw' | sudo fdisk disk.img
  fi
  FS=$TOPDIR/target/sysroot
  if [ ! -d $FS ]; then
    mkdir -p $FS
  fi
  sudo losetup -f disk.img
  DEV=$(sudo losetup -j disk.img | awk -F: '{ print $1 }' | head -1)
  yes | sudo mkfs.ext4 $DEV
  if [ $(find $FS | wc -l) -gt 1 ]; then
    sudo mount $DEV /mnt
    sudo cp -rf $FS/* /mnt
    sudo umount /mnt
  fi
  sudo losetup -D disk.img
}
