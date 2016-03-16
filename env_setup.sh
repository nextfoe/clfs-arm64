
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export TOPDIR=$(pwd)
export SYSROOT=$TOPDIR/target/sysroot
export PATH=$TOPDIR/tools/bin:$PATH
export SYSIMG=$TOPDIR/target/system.img
export CLFS_TARGET=aarch64-linux-gnu
export CLFS_HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
export TOOLDIR=$TOPDIR/tools

JOBS=$(cat /proc/cpuinfo | grep processor | wc -l)


mkdir -p $TOPDIR/{tools,source,build,target,repo}

gdb_attach() {
  aarch64-linux-gnu-gdb --command=./.gdb.cmd
}

croot() {
  cd $TOPDIR
}

download_source() {
  declare -a tarball_list=( \
    "ftp://ftp.gnu.org/gnu/gcc/gcc-5.3.0/gcc-5.3.0.tar.bz2" \
    "http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.4.tar.xz" \
    "ftp://gcc.gnu.org/pub/gcc/infrastructure/isl-0.16.1.tar.bz2" \
    "http://ftp.gnu.org/gnu/gmp/gmp-6.1.0.tar.xz" \
    "http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz" \
    "http://ftp.gnu.org/gnu/libc/glibc-2.23.tar.bz2" \
    "http://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz" \
    "http://ftp.gnu.org/gnu/bash/bash-4.4-rc1.tar.gz" \
    "http://ftp.gnu.org/gnu/coreutils/coreutils-8.23.tar.xz" \
    "http://downloads.sourceforge.net/project/strace/strace/4.11/strace-4.11.tar.xz" \
    "https://www.kernel.org/pub/linux/utils/util-linux/v2.27/util-linux-2.27.tar.xz" \
    "http://download.savannah.gnu.org/releases/sysvinit/sysvinit-2.88dsf.tar.bz2" \
    "http://patches.clfs.org/dev/coreutils-8.23-noman-1.patch" \
    "https://github.com/bminor/binutils-gdb/archive/gdb-7.11-release.tar.gz" \
    "http://zlib.net/zlib-1.2.8.tar.xz" \
    "http://ftp.gnu.org/gnu/gperf/gperf-3.0.4.tar.gz" \
    "https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz" \
    "http://pkg-shadow.alioth.debian.org/releases/shadow-4.2.1.tar.xz" \
    "http://dev.gentoo.org/~blueness/eudev/eudev-1.7.tar.gz" \
    "http://ftp.gnu.org/gnu/findutils/findutils-4.6.0.tar.gz" \
    "http://ftp.gnu.org/gnu/grep/grep-2.23.tar.xz" \
    "ftp://ftp.kernel.org/pub/linux/utils/kbd/kbd-2.0.3.tar.xz" \
    "https://github.com/libcheck/check/archive/0.10.0.tar.gz" \
    "http://www.linux-pam.org/library/Linux-PAM-1.2.1.tar.gz" \
    "http://clfs.org/files/packages/3.0.0/SYSVINIT/bootscripts-cross-lfs-3.0-20140710.tar.xz" \
    "ftp://ftp.vim.org/pub/vim/unix/vim-7.4.tar.bz2" \
    "http://ftp.gnu.org/gnu/gzip/gzip-1.6.tar.xz" \
    "https://github.com/file/file/archive/FILE5_25.tar.gz" \
    "http://ftp.gnu.org/gnu/sed/sed-4.2.2.tar.bz2" \
    "http://ftp.gnu.org/gnu/gawk/gawk-4.1.3.tar.xz" \
  )
  mkdir -p $TOPDIR/tarball
  pushd $TOPDIR/tarball
    for i in "${tarball_list[@]}"; do
      filename=${i##*/}
      if [ ! -f $filename ]; then
        # retry 3 times
        wget $i || wget $i || wget $i || return 1
      fi
    done
  popd
}

build_kernel() {
  mkdir -p $TOPDIR/build/kernel
  pushd $TOPDIR/kernel
    if [ ! -f $TOPDIR/build/kernel/.config ]; then
      ln -sf $TOPDIR/misc/kernel_defconfig $TOPDIR/kernel/arch/arm64/configs/defconfig
      make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=$TOPDIR/build/kernel defconfig
      git checkout $TOPDIR/kernel/arch/arm64/configs/defconfig
    fi
  popd
  pushd $TOPDIR/build/kernel
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j${JOBS} || return 1
    ln -sf $PWD/arch/arm64/boot/Image $TOPDIR/target/
    ln -sf $PWD/vmlinux $TOPDIR/target
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- tools/perf
    cp tools/perf/perf $SYSROOT/usr/bin
  popd
}

# sudo apt-get install libglib2.0-dev libpixman-1-dev libfdt-dev
build_qemu() {
  mkdir -p $TOPDIR/build/qemu
  pushd $TOPDIR/build/qemu
    $TOPDIR/source/qemu/configure \
      --prefix=$TOOLDIR \
      --target-list=aarch64-softmmu \
      --source-path=$TOPDIR/source/qemu || return 1
    make -j${JOBS} || return 1
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
  if [ ! -d $TOPDIR/repo/ltp ]; then
    pushd $TOPDIR/repo
    git clone https://github.com/linux-test-project/ltp.git
    popd
  fi
  if [ ! -e $TOPDIR/source/ltp ]; then
    pushd $TOPDIR/source
    ln -sf ../repo/ltp
    popd
  fi
  pushd $TOPDIR/source/ltp
    make autotools
    $TOPDIR/source/ltp/configure --host=$CLFS_TARGET --prefix=$SYSROOT/opt/ltp || return 1
    make -j${JOBS} || return 1
    make install
  popd
}

build_strace() {
  if [ ! -d $TOPDIR/source/strace-4.11 ]; then
    tar -xf $TOPDIR/tarball/strace-4.11.tar.xz -C $TOPDIR/source/
  fi

  mkdir -p $TOPDIR/build/strace
  pushd $TOPDIR/build/strace
    $TOPDIR/source/strace-4.11/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j${JOBS} || return 1
    make install
  popd
}

# sudo apt-get install autoconf2.13
# sudo apt-get install autopoint
build_shadow() {
  if [ ! -d $TOPDIR/source/shadow-4.2.1 ]; then
    tar -xf $TOPDIR/tarball/shadow-4.2.1.tar.xz -C $TOPDIR/source
    cp $TOPDIR/misc/shadow-src_usermod.c $TOPDIR/source/shadow-4.2.1/src/usermod.c
  fi

  pushd $TOPDIR/source/shadow-4.2.1
    autoreconf -v -f --install
    echo 'shadow_cv_passwd_dir=${SYSROOT}/bin' > config.cache
    ./configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --sysconfdir=$SYSROOT/etc \
    --enable-maintainer-mode \
    --disable-nls \
    --enable-subordinate-ids=no \
    --cache-file=config.cache || return 1
    echo "#define ENABLE_SUBUIDS 1" >> config.h
    make || return 1
    make install
  popd
}

# sudo apt-get install zlib1g-dev
build_toolchain() {
    ## kernel headers
  pushd $TOPDIR/kernel
    make ARCH=arm64 INSTALL_HDR_PATH=$SYSROOT/usr headers_install
    make mrproper
  popd

    ## binutils
  if [ ! -d $TOPDIR/source/binutils-gdb ]; then
    tar -xzf $TOPDIR/tarball/gdb-7.11-release.tar.gz -C $TOPDIR/source/
    mv $TOPDIR/source/binutils-gdb-gdb-7.11-release $TOPDIR/source/binutils-gdb
  fi
  mkdir -p $TOPDIR/build/binutils
  pushd $TOPDIR/build/binutils
    AR=ar AS=as $TOPDIR/source/binutils-gdb/configure \
      --prefix=$TOOLDIR \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --with-sysroot=$SYSROOT \
      --disable-nls \
      --enable-shared \
      --disable-multilib  || return 1
    make configure-host || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd

    ## gcc stage 1
  if [ ! -d $TOPDIR/source/gcc-5.3.0 ]; then
    tar -xjf $TOPDIR/tarball/gcc-5.3.0.tar.bz2 -C $TOPDIR/source
    pushd $TOPDIR/source/gcc-5.3.0
    tar -xf $TOPDIR/tarball/mpfr-3.1.4.tar.xz && ln -sf mpfr-3.1.4 mpfr
    tar -xf $TOPDIR/tarball/gmp-6.1.0.tar.xz &&  ln -sf gmp-6.1.0 gmp
    tar -xzf $TOPDIR/tarball/mpc-1.0.3.tar.gz && ln -sf mpc-1.0.3 mpc
    tar -xjf $TOPDIR/tarball/isl-0.16.1.tar.bz2 && ln -sf isl-0.16.1 isl
    popd
  fi
  mkdir -p $TOPDIR/build/gcc-stage-1
  pushd $TOPDIR/build/gcc-stage-1
    $TOPDIR/source/gcc-5.3.0/configure \
      --build=$CLFS_HOST \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --prefix=$TOOLDIR \
      --with-sysroot=$SYSROOT \
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
    make -j${JOBS} all-gcc all-target-libgcc || return 1
    make install-gcc install-target-libgcc || return 1
  popd

    ## glibc
  if [ ! -d $TOPDIR/source/glibc-2.23 ]; then
    tar -xjf $TOPDIR/tarball/glibc-2.23.tar.bz2 -C $TOPDIR/source
  fi
  VER=$(grep -o '[0-9]\.[0-9]\.[0-9]' $TOPDIR/build/kernel/.config)
  mkdir -p $TOPDIR/build/glibc
  pushd $TOPDIR/build/glibc
    echo "libc_cv_forced_unwind=yes" > config.cache
    echo "libc_cv_c_cleanup=yes" >> config.cache
    echo "install_root=$SYSROOT" > configparms
    BUILD_CC="gcc" CC="${CLFS_TARGET}-gcc" AR="${CLFS_TARGET}-ar" \
    RANLIB="${CLFS_TARGET}-ranlib" $TOPDIR/source/glibc-2.23/configure \
      --build=$CLFS_HOST \
      --host=$CLFS_TARGET \
      --prefix=/usr \
      --libexecdir=/usr/lib/glibc \
      --enable-kernel=$VER \
      --with-binutils=$TOOLDIR/bin/ \
      --with-headers=$SYSROOT/usr/include || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd

  ## gcc stage 2
  mkdir -p $TOPDIR/build/gcc-stage-2
  pushd $TOPDIR/build/gcc-stage-2
    AR=ar LDFLAGS="-Wl,-rpath,$TOOLDIR/lib" \
    $TOPDIR/source/gcc-5.3.0/configure \
      --prefix=$TOOLDIR \
      --build=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --host=$CLFS_HOST \
      --with-sysroot=$SYSROOT \
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
    make -j${JOBS} AS_FOR_TARGET="${CLFS_TARGET}-as" LD_FOR_TARGET="${CLFS_TARGET}-ld" || return 1
    make install || return 1
  popd

  ## gperf
  if [ ! -d $TOPDIR/source/gperf-3.0.4 ]; then
    tar -xzf $TOPDIR/tarball/gperf-3.0.4.tar.gz -C $TOPDIR/source
  fi

  mkdir -p $TOPDIR/build/cross-gperf
  pushd $TOPDIR/build/cross-gperf
    $TOPDIR/source/gperf-3.0.4/configure \
      --prefix=$TOOLDIR \
      --host=$CLFS_HOST \
      --target=$CLFS_TARGET \
      || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd

  ## file
  if [ ! -d $TOPDIR/source/file-FILE5_25 ]; then
    tar -xzf $TOPDIR/tarball/FILE5_25.tar.gz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/file-FILE5_25
    autoreconf --force --install
    ./configure \
    --host=$CLFS_HOST \
    --prefix=$TOOLDIR || return 1
    make -j${JOBS} || return 1
    make install || return 1
    make distclean
  popd
}

build_gcc () {
  mkdir -p $TOPDIR/build/gcc
  pushd $TOPDIR/build/gcc
    $TOPDIR/source/gcc-5.3.0/configure \
      --build=$CLFS_HOST \
      --target=$CLFS_TARGET \
      --host=$CLFS_TARGET \
      --prefix=$SYSROOT/usr/ \
      --enable-shared \
      --disable-nls \
      --enable-c99 \
      --enable-long-long \
      --enable-languages=c,c++ \
      --enable-__cxa_atexit \
      --enable-threads=posix \
      --with-system-zlib \
      --enable-checking=release || return 1
    make -j${JOBS} AS_FOR_TARGET="${CLFS_TARGET}-as" LD_FOR_TARGET="${CLFS_TARGET}-ld" || return 1
    make install || return 1
  popd
}

build_sysvinit() {
  if [ ! -d $TOPDIR/source/sysvinit-2.88dsf ]; then
    tar -xjf $TOPDIR/tarball/sysvinit-2.88dsf.tar.bz2 -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/sysvinit-2.88dsf
    make CC=${CROSS_COMPILE}gcc LDFLAGS=-lcrypt -j${JOBS} || return 1
    mv -v src/{init,halt,shutdown,runlevel,killall5,fstab-decode,sulogin,bootlogd} $SYSROOT/sbin/
    mv -v src/mountpoint $SYSROOT/bin/
    mv -v src/{last,mesg,utmpdump,wall} $SYSROOT/usr/bin/
  popd
}

build_ncurses() {
  if [ ! -d $TOPDIR/source/ncurses-6.0 ]; then
      tar -xzf $TOPDIR/tarball/ncurses-6.0.tar.gz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/ncurses
  pushd $TOPDIR/build/ncurses
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
    make -j${JOBS} || return 1
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
  if [ ! -d $TOPDIR/source/util-linux-2.27 ]; then
    tar -xf $TOPDIR/tarball/util-linux-2.27.tar.xz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/util-linux
  pushd $TOPDIR/build/util-linux
    $TOPDIR/source/util-linux-2.27/configure \
      --host=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --libdir=$SYSROOT/usr/lib64 \
      --with-bashcompletiondir=$SYSROOT/usr/share/bash-completion/completions \
      --without-python \
      --disable-wall \
      --disable-eject \
      || return 1
    make -j8 || return 1
    make install || return 1
    mv -v $SYSROOT/usr/bin/{logger,dmesg,kill,lsblk,more,tailf,umount,wdctl} $SYSROOT/bin
    mv -v $SYSROOT/usr/sbin/{agetty,blkdiscard,blkid,blockdev,cfdisk,chcpu,fdisk,fsck,fsck.minix,fsfreeze,fstrim,hwclock,losetup,mkfs,mkfs.bfs,mkfs.minix,mkswap,pivot_root,raw,sfdisk,swaplabel,sulogin,swapoff,swapon,switch_root,wipefs} $SYSROOT/sbin
  popd
}

build_bash() {
  if [ ! -d $TOPDIR/source/bash-4.4-rc1 ]; then
    tar -xzf $TOPDIR/tarball/bash-4.4-rc1.tar.gz -C $TOPDIR/source
    sed -i '/#define SYS_BASHRC/c\#define SYS_BASHRC "/etc/bash.bashrc"' $TOPDIR/source/bash-4.4-rc1/config-top.h
  fi

  mkdir -p $TOPDIR/build/bash
  pushd $TOPDIR/build/bash
    $TOPDIR/source/bash-4.4-rc1/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j${JOBS} || return 1
    make install
    mv -v $SYSROOT/usr/bin/bash $SYSROOT/bin/
    cd $SYSROOT/bin && ln -sf bash sh
  popd
}

build_coreutils() {
  if [ ! -d $TOPDIR/source/coreutils-8.23 ]; then
    tar -xf $TOPDIR/tarball/coreutils-8.23.tar.xz -C $TOPDIR/source
    pushd $TOPDIR/source/coreutils-8.23
    patch -p1 < $TOPDIR/tarball/coreutils-8.23-noman-1.patch
    popd
  fi

  mkdir -p $TOPDIR/build/coreutils
  pushd $TOPDIR/build/coreutils
    $TOPDIR/source/coreutils-8.23/configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr || return 1
    make -j${JOBS} || return 1
    make install
    mv -v $SYSROOT/usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo,false,ln,ls,mkdir,mknod,mv,pwd,rm,rmdir,stty,sync,true,uname,chroot,head,sleep,nice,test,[} $SYSROOT/bin/
  popd
}

build_zlib() {
  if [ ! -d $TOPDIR/source/zlib-1.2.8 ]; then
    tar -xf $TOPDIR/tarball/zlib-1.2.8.tar.xz -C $TOPDIR/source
  fi

  pushd $TOPDIR/source/zlib-1.2.8
  $TOPDIR/source/zlib-1.2.8/configure \
      --prefix=$SYSROOT/usr/ \
      --libdir=$SYSROOT/usr/lib64 \
    || return 1
    make -j${JOBS} || return 1
    make install
  popd
}

build_libcap() {
  if [ ! -d $TOPDIR/source/libcap-2.25 ]; then
      tar -xf $TOPDIR/tarball/libcap-2.25.tar.xz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/libcap-2.25
    cp $TOPDIR/misc/libcap-Make.Rules Make.Rules
    make
    cp libcap/libcap.so*    $SYSROOT/usr/lib64/
    cp libcap/include/sys/* $SYSROOT/usr/include/sys/
  popd
}

# make sure these packages is installed:
# sudo apt-get install texinfo bison flex
build_binutils_gdb() {
  if [ ! -d $TOPDIR/source/binutils-gdb ]; then
    tar -xzf $TOPDIR/tarball/gdb-7.11-release.tar.gz -C $TOPDIR/source
    mv $TOPDIR/source/binutils-gdb-gdb-7.11-release $TOPDIR/source/binutils-gdb
  fi

  mkdir -p $TOPDIR/build/binutils-gdb
  pushd $TOPDIR/build/binutils-gdb
    $TOPDIR/source/binutils-gdb/configure \
      --host=$CLFS_TARGET \
      --target=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --libdir=$SYSROOT/usr/lib64 \
      --enable-shared || return 1
    make -j${JOBS} || return 1
    make install
  popd
}

build_gperf() {
  mkdir -p $TOPDIR/build/gperf
  pushd $TOPDIR/build/gperf
    $TOPDIR/source/gperf-3.0.4/configure \
      --host=$CLFS_TARGET \
      --target=$CLFS_TARGET \
      --prefix=$SYSROOT/usr \
      --enable-shared || return 1
    make -j${JOBS} || return 1
    make install
  popd
}

build_procps() {
  if [ ! -d $TOPDIR/repo/procps ]; then
    pushd $TOPDIR/repo
    git clone https://gitlab.com/procps-ng/procps.git
    popd
  fi
  if [ ! -e TOPDIR/source/procps ]; then
    pushd $TOPDIR/source
    ln -sf ../repo/procps
    popd
  fi
  pushd $TOPDIR/source/procps
    sed -i '/^AC_FUNC_MALLOC$/d;/^AC_FUNC_REALLOC$/d' configure.ac
    ./autogen.sh || return 1
    ./configure --host=$CLFS_TARGET --prefix=$SYSROOT/usr --libdir=$SYSROOT/usr/lib64 || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_eudev() {
  if [ ! -d $TOPDIR/source/eudev-1.7 ]; then
    tar -xzf $TOPDIR/tarball/eudev-1.7.tar.gz -C $TOPDIR/source
    sed -i '1i\#include <stdint.h>' $TOPDIR/source/eudev-1.7/src/mtd_probe/mtd_probe.h
  fi
  mkdir -p $TOPDIR/build/eudev
  pushd $TOPDIR/build/eudev
    $TOPDIR/source/eudev-1.7/configure --host=$CLFS_TARGET \
    --prefix=$SYSROOT \
    --disable-introspection \
    --disable-gtk-doc-html \
    --disable-gudev \
    --disable-keymap || return 1
    make -j${JOBS} || return 1
    make install || return 1
    cd $SYSROOT/sbin && ln -sf ../bin/udevadm
  popd
}

build_find() {
  if [ ! -d $TOPDIR/source/findutils-4.6.0 ]; then
    tar -xzf $TOPDIR/tarball/findutils-4.6.0.tar.gz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/find
  pushd $TOPDIR/build/find
    echo "gl_cv_func_wcwidth_works=yes" > config.cache
    echo "ac_cv_func_fnmatch_gnu=yes" >> config.cache
    $TOPDIR/source/findutils-4.6.0/configure --host=$CLFS_TARGET \
    --prefix=$SYSROOT \
    --cache-file=config.cache || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_grep() {
  if [ ! -d $TOPDIR/source/grep-2.23 ]; then
    tar -xf $TOPDIR/tarball/grep-2.23.tar.xz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/grep
  pushd $TOPDIR/build/grep
    $TOPDIR/source/grep-2.23/configure --host=$CLFS_TARGET \
    --prefix=$SYSROOT \
    || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_check() {
  if [ ! -d $TOPDIR/source/check-0.10.0 ]; then
    tar -xzf $TOPDIR/tarball/0.10.0.tar.gz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/check-0.10.0
    autoreconf --force --install
    ./configure --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --libdir=$SYSROOT/usr/lib64 || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_file() {
  if [ ! -d $TOPDIR/source/file-FILE5_25 ]; then
    tar -xzf $TOPDIR/tarball/FILE5_25.tar.gz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/file-FILE5_25
    autoreconf --force --install
    ./configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr || return 1
    make -j${JOBS} || return 1
    make install || return 1
    make distclean
  popd
}

build_pam() {
  if [ ! -d $TOPDIR/source/Linux-PAM-1.2.1 ]; then
    tar -xzf $TOPDIR/tarball/Linux-PAM-1.2.1.tar.gz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/Linux-PAM-1.2.1/
    ./configure --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --disable-nis \
    --libdir=$SYSROOT/usr/lib64 || return 1
    make -j${JOBS} || return 1
    make install || return 1
    mkdir -p $SYSROOT/usr/include/security
    cd $SYSROOT/usr/include/security
    for i in $(ls ../{pam*,_pam*}); do ln -sf $i; done
  popd
}

build_kbd() {
  if [ ! -d $TOPDIR/source/kbd-2.0.3 ]; then
    tar -xf $TOPDIR/tarball/kbd-2.0.3.tar.xz -C $TOPDIR/source
    # fix cross-compiled setfont can't find font file issue
    sed -i 's:DATADIR:"/lib/kbd":g' $TOPDIR/source/kbd-2.0.3/src/*.c
  fi
  mkdir -p $TOPDIR/build/kbd
  pushd $TOPDIR/build/kbd
    PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib64/pkgconfig \
    CPPFLAGS="-I$SYSROOT/usr/include" \
    $TOPDIR/source/kbd-2.0.3/configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --datadir=$SYSROOT/lib/kbd \
    || return 1
    make -j${JOBS} || return 1
    make install || return 1
    mv -v $SYSROOT/usr/bin/{kbd_mode,loadkeys,openvt,setfont} $SYSROOT/bin
  popd
}

build_gzip() {
  if [ ! -d $TOPDIR/source/gzip-1.6 ]; then
    tar -xf $TOPDIR/tarball/gzip-1.6.tar.xz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/gzip
  pushd $TOPDIR/build/gzip
    $TOPDIR/source/gzip-1.6/configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --bindir=$SYSROOT/bin \
    || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_sed() {
  if [ ! -d $TOPDIR/source/sed-4.2.2 ]; then
    tar -xjf $TOPDIR/tarball/sed-4.2.2.tar.bz2 -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/sed
  pushd $TOPDIR/build/sed
    $TOPDIR/source/sed-4.2.2/configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --bindir=$SYSROOT/bin \
    || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_awk() {
  if [ ! -d $TOPDIR/source/gawk-4.1.3 ]; then
    tar -xf $TOPDIR/tarball/gawk-4.1.3.tar.xz -C $TOPDIR/source
  fi
  mkdir -p $TOPDIR/build/awk
  pushd $TOPDIR/build/awk
    $TOPDIR/source/gawk-4.1.3/configure \
    --host=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --bindir=$SYSROOT/bin \
    || return 1
    make -j${JOBS} || return 1
    make install || return 1
  popd
}

build_bootscript() {
  if [ ! -d $TOPDIR/source/bootscripts-cross-lfs-3.0-20140710 ]; then
    tar -xf $TOPDIR/tarball/bootscripts-cross-lfs-3.0-20140710.tar.xz -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/bootscripts-cross-lfs-3.0-20140710
    DESTDIR=$SYSROOT make install-bootscripts
    ## HACK! ##
    sed -i '20i\ldconfig' $SYSROOT/etc/rc.d/init.d/rc
    sed -i '$i\bash' $SYSROOT/etc/rc.d/init.d/rc
  popd
}

build_vim() {
  if [ ! -d $TOPDIR/source/vim74 ]; then
    tar -xjf $TOPDIR/tarball/vim-7.4.tar.bz2 -C $TOPDIR/source
  fi
  pushd $TOPDIR/source/vim74
    ./configure \
    --build=$CLFS_HOST \
    --host=$CLFS_TARGET \
    --target=$CLFS_TARGET \
    --prefix=$SYSROOT/usr \
    --with-tlib=tinfo \
    vim_cv_toupper_broken=y \
    vim_cv_terminfo=y \
    vim_cv_tty_group=y \
    vim_cv_tty_mode=y \
    vim_cv_getcwd_broken=y \
    vim_cv_stat_ignores_slash=y \
    vim_cv_bcopy_handles_overlap=y \
    vim_cv_memmove_handles_overlap=y \
    vim_cv_memcpy_handles_overlap=y || return 1
    make -j${JOBS} || return 1
    make install || return 1
    cd $SYSROOT/usr/bin
    ln -sf vim vi
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
