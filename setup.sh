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
# rm -f $ROOT/root/Image

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
    $ROOT/binutils-gdb/configure --prefix=$ROOT/tools --target=aarch64-linux-gnu || exit
    make -j4 || exit
    make install
  popd
fi

# build qemu
qemu-system-aarch64 -version &> /dev/null
if [ $? -ne 0 ]; then
  mkdir -p build/qemu
  pushd build/qemu
    $ROOT/qemu/configure --prefix=$ROOT/tools --target-list=aarch64-softmmu --source-path=$ROOT/qemu || exit
    make -j4 || exit
    make install
  popd
fi

# for place of kernel and rootfs.cpio
mkdir -p root

# build busybox
if [ ! -f $ROOT/root/root.cpio ]; then
  cp $ROOT/configs/busybox_aarch64_defconfig $ROOT/busybox/configs
  pushd busybox
    make busybox_aarch64_defconfig
    make -j4 || exit
    make install || exit
    cd _install
    cp -r $ROOT/configs/etc .
    mkdir -p dev tmp sys proc mnt var
    ln -sf bin/busybox init
    rm -f linuxrc
    find . | cpio -ovHnewc > $ROOT/root/root.cpio
  popd
fi

# build kernel
if [ ! -f $ROOT/root/Image ]; then
  mkdir -p build/kernel
  pushd build/kernel
    cp $ROOT/configs/kernel_defconfig $ROOT/kernel/arch/arm64/configs/user_defconfig
    make -C $ROOT/kernel/ O=$ROOT/build/kernel ARCH=arm64 user_defconfig || exit
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || exit
    cp arch/arm64/boot/Image $ROOT/root
    rm -f $ROOT/kernel/arch/arm64/configs/user_defconfig
  popd
fi

# rebuild
if [ $BUILD -eq 1 ]; then

  pushd build/qemu
    make -j4 || exit
    make install
  popd

  pushd busybox
    make -j4 || exit
    make install || exit
    cd _install
    cp -r $ROOT/configs/etc .
    mkdir -p dev tmp sys proc mnt var
    ln -sf bin/busybox init
    rm -f linuxrc
    find . | cpio -ovHnewc > $ROOT/root/root.cpio
  popd

  pushd build/kernel
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || exit
    cp arch/arm64/boot/Image $ROOT/root/
    cp vmlinux $ROOT/root/
    cp System.map $ROOT/root/
    aarch64-linux-gnu-objdump -d vmlinux > $ROOT/root/dis.s
  popd
fi

mkfs

# Run
run
