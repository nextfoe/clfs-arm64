#!/bin/bash

. env_setup.sh

FORCE_UPDATE=0
FORCE_BUILD=0

usage() {
  echo "usage: $0 [-u] [-b]"
  echo '       -u: git update for each repo'
  echo '       -b: force build qemu & kernel'
}

# parse options
while getopts ":ub" opt; do
  case $opt in
    u) FORCE_UPDATE=1
    ;;
    b) FORCE_BUILD=1
    ;;
    ?) usage; exit
  esac
done

if [ ! -d tarball ]; then
  download_source
fi

# Download qemu source code
if [ ! -d source/qemu ]; then
  cd source
  git clone git://git.qemu-project.org/qemu.git || exit
  cd -
fi

# Download linux kernel code
if [ ! -d kernel ]; then
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git kernel || exit
fi

if [ $FORCE_UPDATE -eq 1 ]; then
  do_update kernel
  do_update source/qemu
fi

# Download toolchain
if [ ! -f $TOPDIR/tools/bin/aarch64-linux-gnu-gcc ]; then
  build_toolchain
fi

# build qemu
qemu-system-aarch64 -version &> /dev/null
if [ $? -ne 0 ]; then
  build_qemu || exit
fi

# build kernel
if [ ! -f $TOPDIR/target/Image ]; then
  build_kernel || exit
fi


if [ ! -f $SYSIMG ]; then
  mkdir -p $SYSROOT/{bin,sbin,etc,dev,tmp,sys,proc,mnt,var,home,root,lib,usr/lib}
  prepare_build_env
  test -f $SYSROOT/usr/lib/libz.so || build_zlib || exit
  test -f $SYSROOT/usr/lib/libcap.so || build_libcap || exit
  test -f $SYSROOT/usr/bin/gdb ||  build_binutils_gdb || exit
# later #  test -f $SYSROOT/usr/bin/gcc || build_gcc || exit
  test -f $SYSROOT/usr/lib/libncurses.so || build_ncurses || exit
  test -f $SYSROOT/sbin/agetty || build_util_linux || exit
  test -f $SYSROOT/bin/bash ||  build_bash || exit
  test -f $SYSROOT/usr/bin/yes || build_coreutils || exit
  test -f $SYSROOT/usr/bin/strace ||  build_strace || exit
  test -d $SYSROOT/opt/ltp || build_ltp || exit
  test -f $SYSROOT/sbin/init || build_systemd || exit
  clean_build_env
  cp -rf $TOPDIR/misc/etc/* $SYSROOT/etc
  new_disk $SYSIMG 2000
fi

# force build
if [ $FORCE_BUILD -eq 1 ]; then
  build_qemu || exit
  build_kernel || exit
fi

# Run
run
