#!/bin/bash

## Author: zhizhou.zh@gmail.com

. source_me.sh

UPDATE=0
BUILD=0

usage() {
  echo "usage: $0 [-u] [-b]"
  echo '       -u: do git update for each repo'
  echo '       -b: build each repo anyway'
}

# parse options
while getopts ":ub" opt; do
  case $opt in
    u) UPDATE=1
    ;;
    b) BUILD=1
    ;;
    ?) usage; exit
  esac
done

# re-build kernel?
# rm -f $TOPDIR/target/Image

# Download qemu source code
if [ ! -d qemu ]; then
  git clone git://git.qemu-project.org/qemu.git || exit
fi

# Download linux kernel code
if [ ! -d kernel ]; then
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git kernel || exit
fi

# Download busybox source code
if [ ! -d busybox ]; then
  git clone git://git.busybox.net/busybox || exit
fi

if [ $UPDATE -eq 1 ]; then
  do_update kernel
  do_update qemu
  do_update busybox
fi

# Download toolchain
${CROSS_COMPILE}gcc -v &> /dev/null
if [ $? -ne 0 ]; then
  wget https://releases.linaro.org/15.06/components/toolchain/binaries/4.8/aarch64-linux-gnu/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz || rm -f gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz && exit
  xz -d gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz
  tar -xf gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar -C tools
  rm gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar
fi

# build gdb if needed
# make sure below packages are installed:
# sudo apt-get install texinfo flex bison
aarch64-linux-gnu-gdb --version &> /dev/null
if [ $? -ne 0 ]; then
  if [ ! -d binutils-gdb ]; then
    git clone git://sourceware.org/git/binutils-gdb.git
  fi
  mkdir -p build/gdb
  pushd build/gdb
    $TOPDIR/binutils-gdb/configure --prefix=$TOPDIR/tools --target=aarch64-linux-gnu || exit
    make -j4 || exit
    make install
  popd
fi

# build qemu
qemu-system-aarch64 -version &> /dev/null
if [ $? -ne 0 ]; then
  mkdir -p build/qemu
  pushd build/qemu
    $TOPDIR/qemu/configure --prefix=$TOPDIR/tools --target-list=aarch64-softmmu --source-path=$TOPDIR/qemu || exit
    make -j4 || exit
    make install
  popd
fi

mkdir -p target

# build busybox
if [ ! -f $ROOTFS ]; then
  pushd busybox
    if [ ! -f $SYSROOT/bin/busybox ]; then
      cp $TOPDIR/configs/busybox_*_defconfig $TOPDIR/busybox/configs
      if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
        make busybox_aarch64_static_defconfig
      else
        make busybox_aarch64_dynamic_defconfig
      fi
      sed -i "/^CONFIG_PREFIX=.*$/d" .config
      echo "CONFIG_PREFIX=\"$SYSROOT\"" >> .config
      make -j4 || exit
      make install || exit
      cp -r $TOPDIR/configs/etc $SYSROOT/
      mkdir -p $SYSROOT/{dev,tmp,sys,proc,mnt,var,lib,usr/lib}
      ln -sf $SYSROOT/bin/busybox $SYSROOT/init
      rm -f $SYSROOT/linuxrc
    fi
    cd $SYSROOT
    if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
      find . | cpio -ovHnewc > $ROOTFS
    else
      cp -rf $TOPDIR/$TOOLCHAIN/aarch64-linux-gnu/libc/usr/lib/* usr/lib/
      cp -rf $TOPDIR/$TOOLCHAIN/aarch64-linux-gnu/libc/lib/ld-linux-aarch64.so.1 lib/
      LTP_INSTALL_DIR=$SYSROOT/ltp
      if [ ! -d $LTP_INSTALL_DIR ]; then
        bltp $LTP_INSTALL_DIR
      fi
      new_disk $ROOTFS 2000
    fi
  popd
fi

# build kernel
if [ ! -f $TOPDIR/target/Image ]; then
  mkdir -p build/kernel
  pushd build/kernel
    cp $TOPDIR/configs/kernel_defconfig $TOPDIR/kernel/arch/arm64/configs/user_defconfig
    make -C $TOPDIR/kernel/ O=$TOPDIR/build/kernel ARCH=arm64 user_defconfig || exit
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || exit
    ln -sf $PWD/arch/arm64/boot/Image $TOPDIR/target
    ln -sf $PWD/vmlinux $TOPDIR/target
    rm -f $TOPDIR/kernel/arch/arm64/configs/user_defconfig
  popd
fi

# rebuild
if [ $BUILD -eq 1 ]; then

  mkdir -p build/{qemu,kernel}

  pushd build/qemu
    if [ ! -f Makefile ]; then
      $TOPDIR/qemu/configure --prefix=$TOPDIR/tools --target-list=aarch64-softmmu --source-path=$TOPDIR/qemu || exit
    fi
    make -j4 || exit
    make install
  popd

  pushd busybox
    make -j4 || exit
    make install || exit
    cd $SYSROOT
    cp -r $TOPDIR/configs/etc .
    mkdir -p dev tmp sys proc mnt var
    ln -sf bin/busybox init
    rm -f linuxrc
    if [ "is$BUILD_BUSYBOX_STATIC" == "isyes" ]; then
      find . | cpio -ovHnewc > $ROOTFS
    fi
  popd

  rebuild_kernel

fi

# Run
run
