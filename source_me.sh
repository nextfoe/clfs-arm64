
export TOPDIR=$(pwd)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export TOOLCHAIN=/tools/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu/
export PATH=$PATH:$TOPDIR/$TOOLCHAIN/bin:$TOPDIR/tools/bin
export BUILD_BUSYBOX_STATIC=no
export SYSROOT=$TOPDIR/target/sysroot
if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
  export ROOTFS=$TOPDIR/target/rootfs.cpio
else
  export ROOTFS=$TOPDIR/target/disk.img
fi

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
if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
  PARAM="-initrd $ROOTFS"
else
  PARAM="--append root=/dev/vda -drive file=$ROOTFS,index=0,media=disk,format=raw"

fi
  qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $TOPDIR/target/Image \
	-nographic $PARAM $*
}

# bltp <install_dir>
bltp() {
  if [ $# -gt 0 ]; then
    INSTALL=$1
  else
    INSTALL=$SYSROOT/ltp
  fi
  pushd $TOPDIR
    if [ ! -d $TOPDIR/ltp ]; then
      git clone https://github.com/linux-test-project/ltp.git
    fi

    CROSS_COMPILE=aarch64-linux-gnu-
    HOST=aarch64-linux-gnu
    export CC=${CROSS_COMPILE}gcc
    export LD=${CROSS_COMPILE}ld
    export AR=${CROSS_COMPILE}ar
    export AS=${CROSS_COMPILE}as
    export RANDLIB=${CROSS_COMPILE}randlib
    export STRIP=${CROSS_COMPILE}strip
    export CXX=${CROSS_COMPILE}g++
    export LDFLAGS=
    export LIBS=-lpthread

    pushd ltp
      make autotools
      ./configure --host=${HOST} --prefix=${INSTALL} || return
      make -j4 || return
      make install
    popd
  popd
}

# mkfs <disk name> <size>
mkfs() {
  size=$(expr $2 \* 1048576)
  qemu-img create -f raw $1 $size
  yes | /sbin/mkfs.ext4 $1
  sudo mount $1 /mnt
  sudo cp -rf $SYSROOT/* /mnt/ &> /dev/null
  sudo umount /mnt
}

######################################
#mkfs name size(in MB)
# this method also works. but it's too messy
######################################
__mkfs_old() {
  if [ ! -f $1 ]; then
    sudo dd if=/dev/zero of=$1 bs=1024k count=$2
    sudo chmod 666 $1
    echo -e 'n\np\n1\n\n\nt\n83\np\nw' | sudo fdisk $1
  fi
  if [ -d $SYSROOT ]; then
    sudo losetup -f $1
    DEV=$(sudo losetup -j $1 | awk -F: '{ print $1 }' | head -1)
    yes | sudo mkfs.ext4 $DEV
    if [ $(find $SYSROOT | wc -l) -gt 1 ]; then
      sudo mount $DEV /mnt
      sudo cp -rf $SYSROOT/* /mnt/
      sudo umount /mnt
    fi
    sudo losetup -D $1
  fi
}
