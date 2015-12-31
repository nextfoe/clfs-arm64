#!/bin/bash

INSTALL=$(pwd)/root/mnt

if [ ! -d ltp ]; then
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
export LDFLAGS=-static
export LIBS=-lpthread

pushd ltp
  make autotools
  ./configure --host=${HOST} --prefix=${INSTALL} || exit
  make || exit
  make install
popd
