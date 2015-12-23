#!/bin/bash

pushd build/kernel
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || exit
  cp arch/arm64/boot/Image $ROOT/root/
  cp vmlinux $ROOT/root/
  cp System.map $ROOT/root/
  aarch64-linux-gnu-objdump -d vmlinux > $ROOT/root/dis.s
popd

. run.sh
