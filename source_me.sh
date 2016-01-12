
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

build_kernel() {
  if [ ! -d $TOPDIR/build/kernel ]; then
    mkdir -p $TOPDIR/build/kernel
  fi
  pushd $TOPDIR/build/kernel
    if [ ! -f .config ]; then
      ln -sf $TOPDIR/configs/kernel_defconfig $TOPDIR/kernel/arch/arm64/configs/user_defconfig
      make -C $TOPDIR/kernel/ O=$TOPDIR/build/kernel ARCH=arm64 user_defconfig
      rm -f user_defconfig
    fi
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || return
    ln -sf $PWD/arch/arm64/boot/Image $TOPDIR/target/
    ln -sf $PWD/vmlinux $TOPDIR/target
  popd
}

build_qemu() {
  if [ ! -d $TOPDIR/build/qemu ]; then
    mkdir -p $TOPDIR/build/qemu
  fi
  pushd $TOPDIR/build/qemu
    if [ ! -f Makefile ]; then
      $TOPDIR/qemu/configure --prefix=$TOPDIR/tools --target-list=aarch64-softmmu --source-path=$TOPDIR/qemu || return
    fi
    make -j4 || return
    make install
  popd
}

do_update() {
  pushd $1
  git pull
  popd
}


run() {
  if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
    qemu-system-aarch64 \
          -machine virt \
          -cpu cortex-a53 \
          -m 512M \
          -kernel $TOPDIR/target/Image \
          -initrd $ROOTFS \
          -nographic $*
  else
    qemu-system-aarch64 \
          -machine virt \
          -cpu cortex-a53 \
          -m 512M \
          -kernel $TOPDIR/target/Image \
	  -smp 4 \
          -drive "file=$ROOTFS,media=disk,format=raw" \
          --append "rootfstype=ext4 rw root=/dev/vda" \
          -nographic $*
  fi
}

prepare_build_env() {
    export CROSS_COMPILE=aarch64-linux-gnu-
    export HOST=aarch64-linux-gnu
    export CC=${CROSS_COMPILE}gcc
    export LD=${CROSS_COMPILE}ld
    export AR=${CROSS_COMPILE}ar
    export AS=${CROSS_COMPILE}as
    export RANDLIB=${CROSS_COMPILE}randlib
    export STRIP=${CROSS_COMPILE}strip
    export CXX=${CROSS_COMPILE}g++
    export LDFLAGS=
    export LIBS=-lpthread
}

clean_build_env() {
    unset CROSS_COMPILE
    unset HOST
    unset CC
    unset LD
    unset AR
    unset AS
    unset RANDLIB
    unset STRIP
    unset CXX
    unset LDFLAGS
    unset LIBS
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

    pushd ltp
      make autotools
      ./configure --host=${HOST} --prefix=${INSTALL} || return
      make -j4 || return
      make install
    popd
  popd
}

# new_disk <disk name> <size>
new_disk() {
  size=$(expr $2 \* 1048576)
  qemu-img create -f raw $1 $size
  yes | /sbin/mkfs.ext4 $1
  sudo mount $1 /mnt
  sudo cp -rf $SYSROOT/* /mnt/ &> /dev/null
  sudo umount /mnt
}
