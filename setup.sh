#!/bin/bash

## Author: zhizhou.zh@gmail.com

. source_me.sh

UPDATE=0
BUILD=0

usage() {
  echo "usage: $0 [-u] [-b]"
  echo '       -u: git update for each repo'
  echo '       -b: force build qemu & kernel'
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

# Download qemu source code
if [ ! -d qemu ]; then
  git clone git://git.qemu-project.org/qemu.git || exit
fi

# Download linux kernel code
if [ ! -d kernel ]; then
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git kernel || exit
fi

if [ $UPDATE -eq 1 ]; then
  do_update kernel
  do_update qemu
fi

# Download toolchain
${CROSS_COMPILE}gcc -v &> /dev/null
if [ $? -ne 0 ]; then
  wget https://releases.linaro.org/15.06/components/toolchain/binaries/4.8/aarch64-linux-gnu/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz || rm -f gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz && exit
  xz -d gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar.xz
  tar -xf gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar -C tools
  rm gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu.tar
fi

# build qemu
qemu-system-aarch64 -version &> /dev/null
if [ $? -ne 0 ]; then
  build_qemu || exit
fi

mkdir -p target

# build kernel
if [ ! -f $TOPDIR/target/Image ]; then
  build_kernel || exit
fi


if [ ! -f $ROOTFS ]; then
  mkdir -p $SYSROOT/{bin,sbin,etc,dev,tmp,sys,proc,mnt,var,home,root,lib,usr/lib}
  prepare_build_env
  test -f $SYSROOT/usr/lib/libc.a || build_glibc || exit
  test -f $SYSROOT/usr/lib/libncurses.so || build_ncurses || exit
  test -f $SYSROOT/sbin/agetty || build_util_linux || exit
  test -d $SYSROOT/ltp || build_ltp || exit
  test -f $SYSROOT/bin/bash ||  build_bash || exit
  test -f $SYSROOT/sbin/init || build_sysvinit || exit
  test -f $SYSROOT/usr/bin/yes || build_coreutils || exit
  test -f $SYSROOT/usr/bin/strace ||  build_strace || exit
  ## failed: because of libncurses. workaround with:
  ## cd gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu/aarch64-linux-gnu/include/ && cp ncurses/* .
  test -f $SYSROOT/usr/bin/gdb ||  build_binutils_gdb || exit
  clean_build_env
  cp -rf $TOPDIR/configs/etc/* $SYSROOT/etc
  new_disk $ROOTFS 2000
fi

# force build
if [ $BUILD -eq 1 ]; then
  build_qemu || exit
  build_kernel || exit
fi

# Run
run
