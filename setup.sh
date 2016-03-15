#!/bin/bash

. env_setup.sh

FORCE_UPDATE=0
FORCE_BUILD=0

usage() {
  echo "usage: $0 [-u] [-b]"
  echo '       -u: git update for each repo'
  echo '       -b: force build qemu & kernel'
}

WORKD=$PWD
die() {
  echo -e "\n**********\033[41m$1 \033[0m**********\n"
  cd $WORKD
  exit 1
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

# check if any package source code is missing
download_source || die "download_source"

# Download qemu source code
if [ ! -d $TOPDIR/repo/qemu ]; then
  cd $TOPDIR/repo
  git clone git://git.qemu-project.org/qemu.git || die "clone qemu"
fi
if [ ! -e $TOPDIR/source/qemu ]; then
  cd $TOPDIR/source
  ln -sf ../repo/qemu
  cd $TOPDIR
fi

# Download linux kernel code
if [ ! -d kernel ]; then
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git kernel || die "clone kernel"
fi

if [ $FORCE_UPDATE -eq 1 ]; then
  do_update kernel
  do_update source/qemu
fi

# build toolchain
if [ ! -f $TOPDIR/tools/bin/aarch64-linux-gnu-gcc ]; then
  build_toolchain || die "build_toolchain"
fi

# build qemu
qemu-system-aarch64 -version &> /dev/null
if [ $? -ne 0 ]; then
  build_qemu || die "build_qemu"
fi

# build kernel
if [ ! -f $TOPDIR/target/Image ]; then
  build_kernel || die "build_kernel"
fi


if [ ! -f $SYSIMG ]; then
  mkdir -p $SYSROOT/{bin,sbin,etc,run,dev,tmp,sys,proc,mnt,var,home,root,lib,usr/lib}
  prepare_build_env
  test -f $SYSROOT/usr/lib64/libz.so || build_zlib || die "build_zlib"
  test -f $SYSROOT/usr/lib64/libcheck.so || build_check || die "build_check"
  test -f $SYSROOT/usr/lib64/libpam.so || build_pam || die "build_pam"
  test -f $SYSROOT/usr/lib64/libcap.so || build_libcap || die "build_libcap"
  test -f $SYSROOT/usr/lib64/libncurses.so || build_ncurses || die "build_ncurses"
  test -f $SYSROOT/usr/bin/gcc || build_gcc || die "build_gcc"
  test -f $SYSROOT/sbin/agetty || build_util_linux || die "build_util_linux"
  test -f $SYSROOT/usr/bin/gdb ||  build_binutils_gdb || die "build_binutils_gdb"
  test -f $SYSROOT/bin/bash ||  build_bash || die "build_bash"
  test -f $SYSROOT/usr/bin/yes || build_coreutils || die "build_coreutils"
  test -f $SYSROOT/usr/bin/strace ||  build_strace || die "build_strace"
  test -f $SYSROOT/usr/bin/login || build_shadow || die "build_shadow"
  test -f $SYSROOT/usr/bin/ps || build_procps || die "build_procps"
  test -f $SYSROOT/sbin/udevd || build_eudev || die "build_eudev"
  test -f $SYSROOT/sbin/init || build_sysvinit || die "build_sysvinit"
  test -f $SYSROOT/bin/find || build_find || die "build_find"
  test -f $SYSROOT/usr/bin/file || build_file || die "build_file"
  test -f $SYSROOT/bin/grep || build_grep || die "build_grep"
  test -f $SYSROOT/bin/sed || build_sed || die "build_sed"
  test -f $SYSROOT/bin/awk || build_awk || die "build_awk"
  test -f $SYSROOT/bin/gzip || build_gzip || die "build_gzip"
  test -f $SYSROOT/bin/loadkeys || build_kbd || die "build_kbd"
  test -f $SYSROOT/usr/bin/vim || build_vim || die "build_vim"
  test -f $SYSROOT/etc/rc.d/init.d/rc || build_bootscript || die "build_bootscript"
#  test -d $SYSROOT/opt/ltp || build_ltp || exit
  clean_build_env
  cp -f $TOPDIR/misc/etc/* $SYSROOT/etc/
  new_disk $SYSIMG 2000
fi

# force build
if [ $FORCE_BUILD -eq 1 ]; then
  build_qemu || die "build_qemu"
  build_kernel || die "build_kernel"
fi

# Run
run
