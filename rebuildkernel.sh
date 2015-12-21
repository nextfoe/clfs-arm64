#!/bin/bash

pushd build/kernel
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || exit
  cp arch/arm64/boot/Image $ROOT/root
popd

. run.sh
