
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export TOPDIR=$(pwd)
export SYSROOT=$TOPDIR/target/sysroot
export PATH=$TOPDIR/tools/bin:$PATH
export SYSIMG=$TOPDIR/target/system.img
export CLFS_TARGET=aarch64-linux-gnu
export CLFS_HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
export TOOLDIR=$TOPDIR/tools

mkdir -p $TOPDIR/{tools,source,build,target}

gdb_attach() {
  aarch64-linux-gnu-gdb --command=./.gdb.cmd
}

croot() {
  cd $TOPDIR
}

download_source() {
  pushd $TOPDIR/tarball
    wget http://ftp.gnu.org/gnu/binutils/binutils-2.26.tar.bz2 || return 1
    wget ftp://ftp.gnu.org/gnu/gcc/gcc-5.3.0/gcc-5.3.0.tar.bz2 || return 1
    wget ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr-2.4.2.tar.bz2 || return 1
    wget ftp://gcc.gnu.org/pub/gcc/infrastructure/gmp-4.3.2.tar.bz2 || return 1
    wget ftp://gcc.gnu.org/pub/gcc/infrastructure/mpc-0.8.1.tar.gz || return 1
    wget ftp://gcc.gnu.org/pub/gcc/infrastructure/isl-0.14.tar.bz2 || return 1
    wget http://ftp.gnu.org/gnu/libc/glibc-2.23.tar.bz2 || return 1
    wget http://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz || return 1
    wget http://ftp.gnu.org/gnu/bash/bash-4.4-rc1.tar.gz || return 1
    wget http://ftp.gnu.org/gnu/coreutils/coreutils-8.23.tar.xz || return 1
    wget http://downloads.sourceforge.net/project/strace/strace/4.11/strace-4.11.tar.xz || return 1
    wget https://www.kernel.org/pub/linux/utils/util-linux/v2.27/util-linux-2.27.tar.xz || return 1
    wget http://download.savannah.gnu.org/releases/sysvinit/sysvinit-2.88dsf.tar.bz2 || return 1
    wget http://patches.clfs.org/dev/coreutils-8.23-noman-1.patch || return 1
    wget https://github.com/bminor/binutils-gdb/archive/gdb-7.11-release.tar.gz || return 1
    wget http://zlib.net/zlib-1.2.8.tar.xz || return 1
    wget http://ftp.gnu.org/gnu/gperf/gperf-3.0.4.tar.gz || return 1
    wget https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz || return 1
    wget https://github.com/systemd/systemd/archive/v229.tar.gz || return 1
  popd
}

build_kernel() {
  mkdir -p $TOPDIR/build/kernel
  cd $TOPDIR/kernel
  if [ ! -f $TOPDIR/build/kernel/.config ]; then
    ln -sf $TOPDIR/misc/kernel_defconfig $TOPDIR/kernel/arch/arm64/configs/defconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=$TOPDIR/build/kernel defconfig
    git checkout $TOPDIR/kernel/arch/arm64/configs/defconfig
  fi
  pushd $TOPDIR/build/kernel
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 || return 1
    ln -sf $PWD/arch/arm64/boot/Image $TOPDIR/target/
    ln -sf $PWD/vmlinux $TOPDIR/target
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- tools/perf
    cp tools/perf/perf $SYSROOT/usr/bin
  popd
}

build_qemu() {
  mkdir -p $TOPDIR/build/qemu
  pushd $TOPDIR/build/qemu
    $TOPDIR/source/qemu/configure \
      --prefix=$TOOLDIR \
      --target-list=aarch64-softmmu \
      --source-path=$TOPDIR/source/qemu || return 1
    make -j4 || return 1
    make install
  popd
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
  pushd $TOPDIR/source
    if [ ! -d ltp ]; then
      git clone --depth=1 https://github.com/linux-test-project/ltp.git
    fi

    cd $TOPDIR/source/ltp
    make autotools
    $TOPDIR/source/ltp/configure --host=$CLFS_TARGET --prefix=$SYSROOT/opt/ltp || return 1
    make -j4 || return 1
    make install
  popd
}

build_strace() {
  pushd $TOPDIR/source
    if [ ! -d strace-4.11 ]; then
      tar -xf $TOPDIR/tarball/strace-4.11.tar.xz -C .
    fi

    mkdir -p $TOPDIR/build/strace
    cd $TOPDIR/build/strace
    $TOPDIR/source/strace-4.11/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j4 || return 1
    make install
  popd
}

build_toolchain() {
  pushd $TOPDIR

    ## kernel headers
    cd $TOPDIR/kernel
    make ARCH=arm64 headers_check
    make ARCH=arm64 INSTALL_HDR_PATH=$TOOLDIR/sysroot/usr headers_install

    ## binutils
    if [ ! -d $TOPDIR/source/binutils-2.26 ]; then
      tar -xjf $TOPDIR/tarball/binutils-2.26.tar.bz2 -C $TOPDIR/source
    fi
    mkdir -p $TOPDIR/build/binutils
    cd $TOPDIR/build/binutils
    AR=ar AS=as $TOPDIR/source/binutils-2.26/configure \
      --prefix=$TOOLDIR \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --with-sysroot=$TOOLDIR/sysroot \
      --disable-nls \
      --enable-shared \
      --disable-multilib  || return 1
    make configure-host || return 1
    make -j4 || return 1
    make install || return 1

    ## gcc stage 1
    if [ ! -d $TOPDIR/source/gcc-5.3.0 ]; then
      tar -xjf $TOPDIR/tarball/gcc-5.3.0.tar.bz2 -C $TOPDIR/source
      cd $TOPDIR/source/gcc-5.3.0
      tar -xjf $TOPDIR/tarball/mpfr-2.4.2.tar.bz2 && ln -sf mpfr-2.4.2 mpfr
      tar -xjf $TOPDIR/tarball/gmp-4.3.2.tar.bz2 &&  ln -sf gmp-4.3.2 gmp
      tar -xzf $TOPDIR/tarball/mpc-0.8.1.tar.gz && ln -sf mpc-0.8.1 mpc
      tar -xjf $TOPDIR/tarball/isl-0.14.tar.bz2 && ln -sf isl-0.14 isl
      cd -
    fi
    mkdir -p $TOPDIR/build/gcc-stage-1
    cd $TOPDIR/build/gcc-stage-1
    $TOPDIR/source/gcc-5.3.0/configure \
      --build=$CLFS_HOST \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --prefix=$TOOLDIR \
      --with-sysroot=$TOOLDIR/sysroot \
      --with-newlib \
      --without-headers \
      --with-native-system-header-dir=/usr/include \
      --disable-nls \
      --disable-shared \
      --disable-decimal-float \
      --disable-libgomp \
      --disable-libmudflap \
      --disable-libssp \
      --disable-libatomic \
      --disable-libitm \
      --disable-libsanitizer \
      --disable-libquadmath \
      --disable-threads \
      --disable-multilib \
      --disable-target-zlib \
      --with-system-zlib \
      --enable-languages=c \
      --enable-checking=release || return 1
    make -j4 all-gcc all-target-libgcc || return 1
    make install-gcc install-target-libgcc || return 1

    ## glibc
    if [ ! -d $TOPDIR/source/glibc-2.23 ]; then
      tar -xjf $TOPDIR/tarball/glibc-2.23.tar.bz2 -C $TOPDIR/source
    fi
    VER=$(grep -o '[0-9]\.[0-9]\.[0-9]' $TOPDIR/build/kernel/.config)
    mkdir -p $TOPDIR/build/glibc
    cd $TOPDIR/build/glibc
    echo "libc_cv_forced_unwind=yes" > config.cache
    echo "libc_cv_c_cleanup=yes" >> config.cache
    echo "install_root=${TOOLDIR}/sysroot" > configparms
    BUILD_CC="gcc" CC="${CLFS_TARGET}-gcc" AR="${CLFS_TARGET}-ar" \
    RANLIB="${CLFS_TARGET}-ranlib" $TOPDIR/source/glibc-2.23/configure \
      --build=$CLFS_HOST \
      --host=$CLFS_TARGET \
      --prefix=/usr \
      --libexecdir=/usr/lib/glibc \
      --enable-kernel=$VER \
      --with-binutils=$TOOLDIR/bin/ \
      --with-headers=$TOOLDIR/sysroot/usr/include || return 1
    make -j4 || return 1
    make install || return 1

    ## gcc stage 2
    mkdir -p $TOPDIR/build/gcc-stage-2
    cd $TOPDIR/build/gcc-stage-2
    AR=ar LDFLAGS="-Wl,-rpath,$TOOLDIR/lib" \
    $TOPDIR/source/gcc-5.3.0/configure \
      --prefix=$TOOLDIR \
      --build=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --host=$CLFS_HOST \
      --with-sysroot=$TOOLDIR/sysroot \
      --enable-shared \
      --enable-c99 \
      --enable-linker-build-id \
      --enable-long-long \
      --with-arch=armv8-a \
      --with-gnu-ld \
      --with-gnu-as \
      --enable-lto \
      --enable-nls \
      --enable-plugin \
      --enable-multiarch \
      --enable-languages=c,c++ \
      --enable-__cxa_atexit \
      --enable-threads=posix \
      --with-system-zlib \
      --enable-checking=release \
      --enable-libstdcxx-time || return 1
    make -j4 AS_FOR_TARGET="${CLFS_TARGET}-as" LD_FOR_TARGET="${CLFS_TARGET}-ld" || return 1
    make install || return 1

    ## gperf
    if [ ! -d $TOPDIR/source/gperf-3.0.4 ]; then
      tar -xzf $TOPDIR/tarball/gperf-3.0.4.tar.gz -C $TOPDIR/source
    fi

    mkdir -p $TOPDIR/build/cross-gperf
    cd $TOPDIR/build/cross-gperf
    $TOPDIR/source/gperf-3.0.4/configure \
      --prefix=$TOOLDIR \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      || return 1
    make -j4 || return 1
    make install || return 1
  popd
}

build_gcc () {
  mkdir -p $TOPDIR/build/gcc-stage-3
  pushd $TOPDIR/build/gcc-stage-3
    $TOPDIR/source/gcc-5.3.0/configure \
      --prefix=$SYSROOT/usr \
      --build=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --host=$CLFS_TARGET \
      --with-sysroot=$SYSROOT \
      --without-isl \
      --with-native-system-header-dir=/usr/include \
      --enable-shared \
      --disable-nls \
      --enable-languages=c,c++ \
      --enable-__cxa_atexit \
      --enable-threads=posix \
      --with-system-zlib \
      --enable-checking=release || return 1
    make -j4 AS_FOR_TARGET="${CLFS_TARGET}-as" LD_FOR_TARGET="${CLFS_TARGET}-ld" || return 1
    make install || return 1
  popd
}

build_sysvinit() {
  pushd $TOPDIR/source
    if [ ! -d sysvinit ]; then
      tar -xjf $TOPDIR/tarball/sysvinit-2.88dsf.tar.bz2 -C .
      mv sysvinit-2.88dsf sysvinit
    fi
    cd sysvinit
    make CC=${CROSS_COMPILE}gcc LDFLAGS=-lcrypt -j4 || return 1
    mv -v src/{init,halt,shutdown,runlevel,killall5,fstab-decode,sulogin,bootlogd} $SYSROOT/sbin/
    mv -v src/mountpoint $SYSROOT/bin/
    mv -v src/{last,mesg,utmpdump,wall} $SYSROOT/usr/bin/
  popd
}

build_ncurses() {
  pushd $TOPDIR/source
    if [ ! -d ncurses-6.0 ]; then
        tar -xzf $TOPDIR/tarball/ncurses-6.0.tar.gz -C .
    fi
#    cp $TOPDIR/misc/ncurses-MKlib_gen.sh $TOPDIR/source/ncurses-6.0/ncurses/base/MKlib_gen.sh
    mkdir -p $TOPDIR/build/ncurses
    cd $TOPDIR/build/ncurses-6.0
    AWK=gawk $TOPDIR/source/ncurses-6.0/configure \
      --build=$CLFS_HOST \
      --host=$CLFS_TARGET \
      --prefix=$SYSROOT/usr  \
      --libdir=$SYSROOT/usr/lib64 \
      --with-termlib=tinfo \
      --without-ada \
      --without-debug \
      --enable-overwrite \
      --with-build-cc=gcc \
      --with-shared || return 1
    make -j4 || return 1
    make install
    cd $SYSROOT/usr/lib64
    ln -sf libncurses.so.6 libcurses.so
    ln -sf libmenu.so.6.0 libmenu.so
    ln -sf libpanel.so.6.0 libpanel.so
    ln -sf libform.so.6 libform.so
    ln -sf libtinfo.so.6.0 libtinfo.so
  popd
}

build_util_linux() {
  pushd $TOPDIR/source
    if [ ! -d util-linux-2.27 ]; then
      tar -xf $TOPDIR/tarball/util-linux-2.27.tar.xz -C .
    fi
    mkdir -p $TOPDIR/build/util-linux
    cd $TOPDIR/build/util-linux
    CPPFLAGS="-I$SYSROOT/usr/include" LDFLAGS="-L$SYSROOT/usr/lib64" \
    $TOPDIR/source/util-linux-2.27/configure \
      --host=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --exec-prefix=$SYSROOT/usr \
      --libdir=$SYSROOT/usr/lib64 \
      --without-python \
      --with-bashcompletiondir=$SYSROOT/usr/share/bash-completion/completions \
      --disable-wall \
      || return 1
    make -j8 || return 1
    make install || return 1
    mv -v $SYSROOT/usr/bin/{logger,dmesg,kill,lsblk,more,tailf,umount,wdctl} $SYSROOT/bin
    mv -v $SYSROOT/usr/sbin/{agetty,blkdiscard,blkid,blockdev,cfdisk,chcpu,fdisk,fsck,fsck.minix,fsfreeze,fstrim,hwclock,losetup,mkfs,mkfs.bfs,mkfs.minix,mkswap,pivot_root,raw,sfdisk,swaplabel,sulogin,swapoff,swapon,switch_root,wipefs} $SYSROOT/sbin
  popd
}

build_bash() {
  pushd $TOPDIR/source
    if [ ! -d bash-4.4-rc1 ]; then
      tar -xzf $TOPDIR/tarball/bash-4.4-rc1.tar.gz -C .
      cd bash-4.4-rc1
      sed -i '/#define SYS_BASHRC/c\#define SYS_BASHRC "/etc/bash.bashrc"' config-top.h
      cd -
    fi

    mkdir -p $TOPDIR/build/bash
    cd $TOPDIR/build/bash
    $TOPDIR/source/bash-4.4-rc1/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j4 || return 1
    make install
    mv -v $SYSROOT/usr/bin/bash $SYSROOT/bin/
  popd
}

build_coreutils() {
  pushd $TOPDIR/source
    if [ ! -d coreutils-8.23 ]; then
      tar -xf $TOPDIR/tarball/coreutils-8.23.tar.xz -C .
      cd coreutils-8.23
      patch -p1 < $TOPDIR/tarball/coreutils-8.23-noman-1.patch
      cd -
    fi

    mkdir -p $TOPDIR/build/coreutils
    cd $TOPDIR/build/coreutils
    $TOPDIR/source/coreutils-8.23/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j4 || return 1
    make install
    mv -v $SYSROOT/usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo,false,ln,ls,mkdir,mknod,mv,pwd,rm,rmdir,stty,sync,true,uname,chroot,head,sleep,nice,test,[} $SYSROOT/bin/
  popd
}

build_zlib() {
  pushd $TOPDIR/source
    if [ ! -d zlib-1.2.8 ]; then
      tar -xf $TOPDIR/tarball/zlib-1.2.8.tar.xz -C .
    fi

    cd $TOPDIR/source/zlib-1.2.8
    $TOPDIR/source/zlib-1.2.8/configure \
      --prefix=$SYSROOT/usr \
      --libdir=$SYSROOT/usr/lib64 \
    || return 1
    make -j4 || return 1
    make install
  popd
}

build_libcap() {
  pushd $TOPDIR/source
    if [ ! -d libcap-2.25 ]; then
      tar -xf $TOPDIR/tarball/libcap-2.25.tar.xz -C .
    fi
    cd libcap-2.25
    cp $TOPDIR/misc/libcap-Make.Rules Make.Rules
    make
    cp libcap/libcap.so* $SYSROOT/usr/lib64/
    cp -r libcap/include/sys/ $SYSROOT/usr/include/
  popd
}

# make sure these packages is installed:
# sudo apt-get install texinfo bison flex
build_binutils_gdb() {
  pushd $TOPDIR/source
    if [ ! -d binutils-gdb ]; then
      tar -xzf $TOPDIR/tarball/gdb-7.11-release.tar.gz -C .
      mv binutils-gdb-gdb-7.11-release binutils-gdb
    fi

    mkdir -p $TOPDIR/build/binutils-gdb
    cd $TOPDIR/build/binutils-gdb
    $TOPDIR/source/binutils-gdb/configure \
      --host=$CLFS_TARGET \
      --target=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --libdir=$SYSROOT/usr/lib64 \
      --enable-shared || return 1
    make -j4 || return 1
    make install
  popd
}

build_gperf() {
  pushd $TOPDIR/source
    mkdir -p $TOPDIR/build/gperf
    cd $TOPDIR/build/gperf
    $TOPDIR/source/gperf-3.0.4/configure \
      --host=$CLFS_TARGET \
      --target=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --enable-shared || return 1
    make -j4 || return 1
    make install
  popd
}

# make sure these packages is installed:
# sudo apt-get install libtool
build_systemd() {
  pushd $TOPDIR/source
    if [ ! -d systemd-229 ]; then
      tar -xzf $TOPDIR/tarball/v229.tar.gz -C .
    fi

    cd $TOPDIR/source/systemd-229
    ./autogen.sh
    CPPFLAGS="-I$SYSROOT/usr/include" LDFLAGS="-L$SYSROOT/usr/lib64" \
    PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib64/pkgconfig \
    ./configure \
      --host=$CLFS_TARGET \
      --target=$CLFS_TARGET \
      --with-sysroot=$SYSROOT \
      --prefix=$SYSROOT/usr \
      --exec-prefix=$SYSROOT/usr \
      --sysconfdir=$SYSROOT/etc \
      --localstatedir=$SYSROOT/var \
      --libexecdir=$SYSROOT/usr/lib64 \
      --libdir=$SYSROOT/usr/lib64 \
      --with-rootprefix=$SYSROOT \
      --with-rootlibdir=$SYSROOT/lib64 \
      --with-sysvinit-path=$SYSROOT/etc/init.d \
      --docdir=$SYSROOT/usr/share/doc/systemd-229 \
      --without-python \
      --disable-dbus \
      --disable-kdbus \
      cc_cv_CFLAGS__flto=no || return 1
    make -j4 || return 1
    make install
    cd $SYSROOT/sbin && ln -sf ../lib/systemd/systemd init
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
