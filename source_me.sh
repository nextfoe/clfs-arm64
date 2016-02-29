
export TOPDIR=$(pwd)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export SYSROOT=$TOPDIR/target/sysroot
export SYSIMG=$TOPDIR/target/disk.img
export CLFS_TARGET=aarch64-linux-gnu
export PATH=$TOPDIR/tools/bin:$PATH
export CLFS_HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')

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
        -drive "file=$SYSIMG,media=disk,format=raw" \
        --append "rootfstype=ext4 rw root=/dev/vda earlycon" \
        -nographic $*
}

prepare_build_env() {
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

    mkdir -p build/ltp
    pushd build/ltp
      make autotools
      $TOPDIR/ltp/configure --host=$CLFS_TARGET --prefix=$SYSROOT/ltp || return 1
      make -j4 || return 1
      make install
    popd
  popd
}

build_strace() {
  pushd $TOPDIR
    if [ ! -d $TOPDIR/strace-4.11 ]; then
      wget http://downloads.sourceforge.net/project/strace/strace/4.11/strace-4.11.tar.xz || return
      tar -xf strace-4.11.tar.xz
    fi

    mkdir -p build/strace
    pushd build/strace
      $TOPDIR/strace-4.11/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
      make -j4 || return 1
      make install
    popd
  popd
}

build_toolchain() {
  pushd $TOPDIR

    ## kernel headers
    pushd $TOPDIR/kernel
      make ARCH=arm64 headers_check
      make ARCH=arm64 INSTALL_HDR_PATH=$TOPDIR/tools headers_install
    popd

    ## binutils
    if [ ! -d $TOPDIR/binutils-2.26 ]; then
      wget http://ftp.gnu.org/gnu/binutils/binutils-2.26.tar.bz2 || return 1
      tar -xjf binutils-2.26.tar.bz2
    fi
    mkdir -p build/binutils
      pushd build/binutils
      AR=ar AS=as $TOPDIR/binutils-2.26/configure \
        --prefix=/tools --host=$CLFS_HOST --target=$CLFS_TARGET \
        --with-sysroot=$TOPDIR/tools --with-lib-path=/tools/lib \
        --disable-nls --disable-static --disable-multilib --disable-werror || return 1
      make -j4 || return 1
      make install || return 1
    popd

    ## gcc stage 1
    if [ ! -d $TOPDIR/gcc-5.3.0 ]; then
      wget ftp://ftp.gnu.org/gnu/gcc/gcc-5.3.0/gcc-5.3.0.tar.bz2 || return 1
      tar -xjf gcc-5.3.0.tar.bz2
      cd gcc-5.3.0
      ./contrib/download_prerequisites
      echo -en '\n#undef STANDARD_STARTFILE_PREFIX_1\n#define STANDARD_STARTFILE_PREFIX_1 "$TOPDIR/tools/lib/"\n' >> gcc/config/linux.h
      echo -en '\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_2 ""\n' >> gcc/config/linux.h
      cd -
    fi
    touch $TOPDIR/tools/include/limits.h
    mkdir -p build/gcc-stage-1
    pushd build/gcc-stage-1
      $TOPDIR/gcc-5.3.0/configure --prefix=$TOPDIR/tools \
        --build=$CLFS_HOST --host=$CLFS_HOST --target=$CLFS_TARGET \
        --with-sysroot=$TOPDIR/tools --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include --disable-nls --disable-shared \
        --without-headers --with-newlib --disable-decimal-float --disable-libgomp \
        --disable-libmudflap --disable-libssp --disable-libatomic --disable-libitm \
        --disable-libsanitizer --disable-libquadmath --disable-threads \
        --disable-multilib --disable-target-zlib --with-system-zlib \
        --enable-languages=c --enable-checking=release || return 1
      make -j4 all-gcc all-target-libgcc || return 1
      make install-gcc install-target-libgcc || return 1
    popd

    ## glibc
    if [ ! -d $TOPDIR/glibc-2.23 ]; then
      wget http://ftp.gnu.org/gnu/libc/glibc-2.23.tar.bz2
      tar -xjf glibc-2.23.tar.bz2
    fi
    VER=$(grep -o '[0-9]\.[0-9]\.[0-9]' $TOPDIR/build/kernel/.config)
    mkdir -p build/glibc
    pushd build/glibc
      BUILD_CC="gcc" CC="${CLFS_TARGET}-gcc" AR="${CLFS_TARGET}-ar" \
      RANLIB="${CLFS_TARGET}-ranlib" $TOPDIR/glibc-2.23/configure \
        --build=$CLFS_HOST --host=$CLFS_TARGET \
        --prefix=/tools --libexecdir=/usr/lib/glibc --enable-kernel=$VER \
        --with-binutils=/tools/bin/ \
        --with-headers=/tools/include || return 1
      make -j4 || return 1
      make install || return 1
    popd

    ## gcc stage 2
    mkdir -p build/gcc-stage-2
    pushd build/gcc-stage-2
      AR=ar LDFLAGS="-Wl,-rpath,$TOPDIR/tools/lib" \
      $TOPDIR/gcc-5.3.0/configure --prefix=$TOPDIR/tools \
        --build=$CLFS_HOST --target=$CLFS_TARGET --host=$CLFS_HOST \
        --with-sysroot=$TOPDIR/tools --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include --disable-nls \
        --disable-static --enable-languages=c,c++ --enable-__cxa_atexit \
        --enable-threads=posix --disable-multilib --with-system-zlib \
        --enable-checking=release --enable-libstdcxx-time || return 1
      make -j4 AS_FOR_TARGET="${CLFS_TARGET}-as" LD_FOR_TARGET="${CLFS_TARGET}-ld" || return 1
      make install || return 1
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
    if [ ! -d ncurses-6.0 ]; then
        wget http://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz
        tar -xzf ncurses-6.0.tar.gz
    fi
    PREFIX=$SYSROOT/usr
    mkdir -p build/ncurses
    pushd build/ncurses
      $TOPDIR/ncurses-6.0/configure --host=$CLFS_TARGET --with-termlib=tinfo --without-ada --with-shared --prefix=$PREFIX || return 1
      make -j8 || return 1
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
    if [ ! -d util-linux-2.27 ]; then
      wget https://www.kernel.org/pub/linux/utils/util-linux/v2.27/util-linux-2.27.tar.xz || return 1
      tar -xf util-linux-2.27.tar.xz
    fi
    mkdir -p build/util-linux
    pushd build/util-linux
      CPPFLAGS="-I$TOPDIR/$TOOLCHAIN/aarch64-linux-gnu/libc/usr/include/ncurses" $TOPDIR/util-linux-2.27/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
      make -j8 || return 1
      make install # FIXME: failed, some programs are not installed correctly.. maybe works well with --with-sysroot=$SYSROOT/usr ?
      mv -v ./{logger,dmesg,kill,lsblk,more,tailf,umount,wdctl} $SYSROOT/bin
      mv -v ./{agetty,blkdiscard,blkid,blockdev,cfdisk,chcpu,fdisk,fsck,fsck.minix,fsfreeze,fstrim,hwclock,isosize,losetup,mkfs,mkfs.bfs,mkfs.minix,mkswap,pivot_root,raw,sfdisk,swaplabel,sulogin,swapoff,swapon,switch_root,wipefs} $SYSROOT/sbin
    popd
  popd
}

build_bash() {
  pushd $TOPDIR
    if [ ! -d bash-4.4-rc1 ]; then
      wget http://ftp.gnu.org/gnu/bash/bash-4.4-rc1.tar.gz || return 1
      tar -xf bash-4.4-rc1
      cd bash-4.4-rc1
      sed -i '/#define SYS_BASHRC/c\#define SYS_BASHRC "/etc/bash.bashrc"' config-top.h
      cd -
    fi

    mkdir -p build/bash
    pushd build/bash
      $TOPDIR/bash-4.4-rc1/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
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

    mkdir -p build/coreutils
    pushd build/coreutils
      $TOPDIR/coreutils-8.23/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
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

    mkdir -p build/binutils
    pushd build/binutils
      $TOPDIR/binutils-gdb/configure --host=$CLFS_TARGET --target=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
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
