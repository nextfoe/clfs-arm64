
export TOPDIR=$(pwd)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export TOOLCHAIN=tools/gcc-linaro-4.8-2015.06-x86_64_aarch64-linux-gnu/
export PATH=$TOPDIR/$TOOLCHAIN/bin:$TOPDIR/tools/bin:$PATH
export SYSROOT=$TOPDIR/target/sysroot
export ROOTFS=$TOPDIR/target/disk.img

gdb_attach() {
  aarch64-linux-gnu-gdb --command=./.gdb.cmd
}

croot() {
  cd $TOPDIR
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
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || return 1
    ln -sf $PWD/arch/arm64/boot/Image $TOPDIR/target/
    ln -sf $PWD/vmlinux $TOPDIR/target
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- tools/perf
    cp tools/perf/perf $SYSROOT/usr/bin
  popd
  return 0
}

build_qemu() {
  if [ ! -d $TOPDIR/build/qemu ]; then
    mkdir -p $TOPDIR/build/qemu
  fi
  pushd $TOPDIR/build/qemu
    if [ ! -f Makefile ]; then
      $TOPDIR/qemu/configure --prefix=$TOPDIR/tools --target-list=aarch64-softmmu --source-path=$TOPDIR/qemu || return
    fi
    make -j4 || return 1
    make install
  popd
  return 0
}

do_update() {
  pushd $1
  git pull
  popd
}


run() {
  qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $TOPDIR/target/Image \
        -smp 1 \
        -drive "file=$ROOTFS,media=disk,format=raw" \
        --append "rootfstype=ext4 rw root=/dev/vda earlycon" \
        -nographic $*
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

build_ltp() {
  pushd $TOPDIR
    if [ ! -d $TOPDIR/ltp ]; then
      git clone --depth=1 https://github.com/linux-test-project/ltp.git
    fi

    pushd ltp
      make autotools
      ./configure --host=$HOST --prefix=$SYSROOT/ltp || return 1
      make -j4 || return 1
      make install
    popd
  popd
}

build_strace() {
  pushd $TOPDIR
    if [ ! -d $TOPDIR/strace-4.11 ]; then
      wget http://downloads.sourceforge.net/project/strace/strace/4.11/strace-4.11.tar.xz || return
      xz -d strace-4.11.tar.xz
      tar -xf strace-4.11.tar
      rm strace-4.11.tar
    fi

    pushd strace-4.11
      ./configure --host=$HOST --prefix=$SYSROOT/usr || return 1
      make -j4 || return 1
      make install
    popd
  popd
}

kernel_header() {
  pushd build/kernel
    make ARCH=arm64 headers_check
    make ARCH=arm64 INSTALL_HDR_PATH=$TOPDIR/tools headers_install
  popd
}

build_glibc() {
  pushd $TOPDIR
    if [ ! -d $TOPDIR/glibc-2.23 ]; then
      wget http://ftp.gnu.org/gnu/libc/glibc-2.23.tar.bz2
      tar -xjf glibc-2.23.tar.bz2
    fi
    VER=$(grep -o '[0-9]\.[0-9]\.[0-9]' $TOPDIR/build/kernel/.config)
    mkdir -p build/glibc
    pushd build/glibc
      $TOPDIR/glibc-2.23/configure --host=$HOST --prefix=$SYSROOT/usr --enable-kernel=$VER --with-binutils=$TOPDIR/$TOOLCHAIN/bin/ --with-headers=$TOPDIR/tools/include || return 1
      make -j4 || return 1
      make install
    popd
  popd
}

build_sysvinit() {
  pushd $TOPDIR
    if [ ! -d sysvinit ]; then
      wget http://download.savannah.gnu.org/releases/sysvinit/sysvinit-2.88dsf.tar.bz2
      tar -xjf sysvinit-2.88dsf.tar.bz2
      mv sysvinit-2.88dsf sysvinit
    fi
    pushd sysvinit
      make CC=${CROSS_COMPILE}gcc LDFLAGS=-lcrypt -j4 || return 1
      mv -v src/{init,halt,shutdown,runlevel,killall5,fstab-decode,sulogin,bootlogd} $SYSROOT/sbin/
      mv -v src/mountpoint $SYSROOT/bin/
      mv -v src/{last,mesg,utmpdump,wall} $SYSROOT/usr/bin/
    popd
  popd
}

build_ncurses() {
  pushd $TOPDIR
    if [ ! -d ncurses ]; then
        wget http://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz
        tar -xzf ncurses-6.0.tar.gz
        mv ncurses-6.0 ncurses
    fi
    PREFIX=$TOPDIR/$TOOLCHAIN/aarch64-linux-gnu/libc/usr
    pushd ncurses
      ./configure --host=$HOST --with-termlib=tinfo --without-ada --with-shared --prefix=$PREFIX || return 1
      make -j8
      make install
      cd $PREFIX/lib
      ln -sf libncurses.so.6 libcurses.so
      ln -sf libmenu.so.6.0 libmenu.so
      ln -sf libpanel.so.6.0 libpanel.so
      ln -sf libform.so.6 libform.so
      ln -sf libtinfo.so.6.0 libtinfo.so
    popd
  popd
}

build_util_linux() {
  pushd $TOPDIR
    if [ ! -d util-linux ]; then
      wget https://www.kernel.org/pub/linux/utils/util-linux/v2.27/util-linux-2.27.tar.xz || return 1
      tar -xf util-linux-2.27.tar.xz
      mv util-linux-2.27 util-linux
    fi
    pushd util-linux
      CPPFLAGS="-I$TOPDIR/$TOOLCHAIN/aarch64-linux-gnu/libc/usr/include/ncurses" ./configure --host=$HOST --prefix=$SYSROOT/usr || return 1
      make -j8 || return 1
      make install # FIXME: failed, some programs are not installed correctly.. maybe works well with --with-sysroot=$SYSROOT/usr ?
      mv -v ./{logger,dmesg,kill,lsblk,more,tailf,umount,wdctl} $SYSROOT/bin
      mv -v ./{agetty,blkdiscard,blkid,blockdev,cfdisk,chcpu,fdisk,fsck,fsck.minix,fsfreeze,fstrim,hwclock,isosize,losetup,mkfs,mkfs.bfs,mkfs.minix,mkswap,pivot_root,raw,sfdisk,swaplabel,sulogin,swapoff,swapon,switch_root,wipefs} $SYSROOT/sbin
    popd
  popd
}

build_bash() {
  pushd $TOPDIR
    test -d bash || git clone --depth=1 git://git.savannah.gnu.org/bash.git || return

    pushd bash
      sed -i '/#define SYS_BASHRC/c\#define SYS_BASHRC "/etc/bash.bashrc"' config-top.h
      ./configure --host=$HOST --prefix=$SYSROOT/usr || return 1
      make -j4 || return 1
      make install
      mv -v $SYSROOT/usr/bin/bash $SYSROOT/bin/
    popd
  popd
}

build_coreutils() {
  pushd $TOPDIR
    if [ ! -d coreutils-8.23 ]; then
      wget http://ftp.gnu.org/gnu/coreutils/coreutils-8.23.tar.xz || return 1
      tar -xf coreutils-8.23.tar.xz
      cd coreutils-8.23
      wget http://patches.clfs.org/dev/coreutils-8.23-noman-1.patch || return 1
      patch -p1 < ./coreutils-8.23-noman-1.patch
      cd -
    fi

    pushd coreutils-8.23
      ./configure --host=$HOST --prefix=$SYSROOT/usr || return 1
      make -j4 || return 1
      make install
      mv -v $SYSROOT/usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo,false,ln,ls,mkdir,mknod,mv,pwd,rm,rmdir,stty,sync,true,uname,chroot,head,sleep,nice,test,[} $SYSROOT/bin/
    popd
  popd
}

# make sure these packages is installed:
# sudo apt-get install texinfo bison flex
build_binutils_gdb() {
  pushd $TOPDIR
    if [ ! -d binutils-gdb ]; then
      wget https://github.com/bminor/binutils-gdb/archive/gdb-7.11-release.tar.gz
      tar -xzf gdb-7.11-release.tar.gz
      mv binutils-gdb-gdb-7.11-release binutils-gdb
    fi

    pushd binutils-gdb
      ./configure --host=$HOST --target=$HOST --prefix=$SYSROOT/usr || return 1
      make -j4 || return 1
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
