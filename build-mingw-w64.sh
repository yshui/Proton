#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Makes a local build of mingw-w64 in this directory and installs it to the given path."
    echo ""
    echo "usage:"
    echo -e "\t$0 <installation path e.g. \$HOME/.local>"
    exit 1
fi

if [ -z "$MAKEFLAGS" ]; then
    JOBS=-j$(($(nproc) - 1))
fi

DST_DIR="$1"

BINUTILS_VER=2.32
BINUTILS_SRCTARBALL=binutils-$BINUTILS_VER.tar.xz
BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/$BINUTILS_SRCTARBALL"
BINUTILS_SRCDIR=binutils-$BINUTILS_VER

GCC_VER=9.2.0
GCC_SRCTARBALL=gcc-$GCC_VER.tar.xz
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/$GCC_SRCTARBALL"
GCC_SRCDIR=gcc-$GCC_VER

MINGW_W64_GITVER=v6.0.0
MINGW_W64_GITURL="git://git.code.sf.net/p/mingw-w64/mingw-w64"
MINGW_W64_SRCDIR=mingw-w64-git

ISL_VER=0.21
ISL_SRCTARBALL=isl-$ISL_VER.tar.bz2
ISL_URL="http://isl.gforge.inria.fr/isl-$ISL_VER.tar.bz2"
ISL_SRCDIR=isl-$ISL_VER

function setup_src {
    if [ ! -e "$BINUTILS_SRCTARBALL" ]; then
        wget -O "$BINUTILS_SRCTARBALL" "$BINUTILS_URL"
    fi

    if [ ! -e "$BINUTILS_SRCDIR" ]; then
        tar -xf "$BINUTILS_SRCTARBALL"
        for f in $(dirname $0)/mingw-w64-patches/binutils-*; do
            patch -d "$BINUTILS_SRCDIR" -p1 < $f
        done
    fi

    if [ ! -e "$ISL_SRCTARBALL" ]; then
        wget -O "$ISL_SRCTARBALL" "$ISL_URL"
    fi

    if [ ! -e "$ISL_SRCDIR" ]; then
        tar -xf "$ISL_SRCTARBALL"
    fi

    if [ ! -e "$GCC_SRCTARBALL" ]; then
        wget -O "$GCC_SRCTARBALL" "$GCC_URL"
    fi

    if [ ! -e "$GCC_SRCDIR" ]; then
        tar -xf "$GCC_SRCTARBALL"
        ln -s ../$ISL_SRCDIR $GCC_SRCDIR/isl
    fi

    if [ ! -e "$MINGW_W64_SRCDIR" ]; then
        #shallow clone, we just want this one version
        git clone -b $MINGW_W64_GITVER --depth 1 \
            "$MINGW_W64_GITURL" "$MINGW_W64_SRCDIR"
    fi
}

function build_arch {
    BUILD_ARCH=$(gcc -dumpmachine) #machine which is building the compiler
    HOST_ARCH=$1 #machine which will run the compiler
    WIN32_TARGET_ARCH=$2 #machine which we are building for
    NEWPATH=$DST_DIR/bin:$PATH

    mkdir -p build-$WIN32_TARGET_ARCH/
    pushd build-$WIN32_TARGET_ARCH/

        mkdir -p binutils/
        pushd binutils/
            if [ ! -e Makefile ]; then
                ../../$BINUTILS_SRCDIR/configure \
                    --prefix=$DST_DIR/ \
                    --build=$BUILD_ARCH \
                    --host=$HOST_ARCH \
                    --target=$WIN32_TARGET_ARCH \
                    --enable-lto \
                    --enable-plugins \
                    --enable-deterministic-archives \
                    --disable-multilib \
                    --disable-nls \
                    --disable-werror \
                    $BINUTILS_EXTRA_CONFIGURE
            fi
            make $JOBS configure-host
            make $JOBS LDFLAGS=-all-static
            make $JOBS install
        popd

        mkdir -p mingw-w64-headers/
        pushd mingw-w64-headers/
            if [ ! -e Makefile ]; then
                PATH=$NEWPATH:$PATH ../../$MINGW_W64_SRCDIR/mingw-w64-headers/configure \
                    --prefix=$DST_DIR/$WIN32_TARGET_ARCH/ \
                    --host=$WIN32_TARGET_ARCH \
                    --enable-sdk=all \
                    --enable-secure-api \
                    --enable-idl \
                    $MINGW_W64_HEADERS_EXTRA_CONFIGURE
            fi
            PATH=$NEWPATH:$PATH make $JOBS install
        popd

        mkdir -p gcc/
        pushd gcc/
            if [ ! -e Makefile ]; then
                #arguments mostly taken from Arch AUR mingw-w64-gcc PKGBUILD,
                #except "--disable-dw2-exceptions" swapped for "--disable-sjlj-exceptions --with-dwarf2"
                #for performance reasons on 32-bit
                LDFLAGS=-static PATH=$NEWPATH:$PATH ../../$GCC_SRCDIR/configure \
                    --prefix=$DST_DIR/ \
                    --build=$BUILD_ARCH \
                    --host=$HOST_ARCH \
                    --target=$WIN32_TARGET_ARCH \
                    --enable-static \
                    --enable-shared \
                    --enable-languages=c,lto,c++ \
                    --disable-multilib \
                    --enable-threads=posix \
                    --enable-fully-dynamic-string \
                    --enable-libstdcxx-time=yes \
                    --enable-libstdcxx-filesystem-ts=yes \
                    --enable-cloog-backend=isl \
                    --enable-libgomp \
                    --enable-lto \
                    --disable-sjlj-exceptions \
                    --with-dwarf2 \
                    $GCC_EXTRA_CONFIGURE
            fi
            PATH=$NEWPATH make $JOBS all-gcc
            PATH=$NEWPATH make $JOBS install-gcc
        popd

        mkdir -p mingw-w64-crt/
        pushd mingw-w64-crt/
            if [ ! -e Makefile ]; then
                PATH=$NEWPATH ../../$MINGW_W64_SRCDIR/mingw-w64-crt/configure \
                    --prefix=$DST_DIR/$WIN32_TARGET_ARCH/ \
                    --host=$WIN32_TARGET_ARCH \
                    $MINGW_W64_CRT_EXTRA_CONFIGURE
            fi
            PATH=$NEWPATH make $JOBS
            PATH=$NEWPATH make $JOBS install
        popd

        mkdir -p mingw-w64-winpthreads/
        pushd mingw-w64-winpthreads/
            if [ ! -e Makefile ]; then
                PATH=$NEWPATH ../../$MINGW_W64_SRCDIR/mingw-w64-libraries/winpthreads/configure \
                    --prefix=$DST_DIR/$WIN32_TARGET_ARCH/ \
                    --host=$WIN32_TARGET_ARCH \
                    $MINGW_W64_WINPTHREADS_EXTRA_CONFIGURE
            fi
            PATH=$NEWPATH make $JOBS
            PATH=$NEWPATH make $JOBS install
        popd

        pushd gcc/
            #next step requires libgcc in default library location, but
            #"canadian" build doesn't handle that, so install it explicitly
            PATH=$NEWPATH make configure-target-libgcc
            PATH=$NEWPATH make -C $WIN32_TARGET_ARCH/libgcc $JOBS
            PATH=$NEWPATH make -C $WIN32_TARGET_ARCH/libgcc $JOBS install

            #install libstdc++ and other stuff
            PATH=$NEWPATH make $JOBS
            PATH=$NEWPATH make $JOBS install

            #libstdc++ requires that libstdc++ is installed in order to find gettimeofday(???)
            #so, rebuild libstdc++ after installing it above
            PATH=$NEWPATH make $JOBS -C $WIN32_TARGET_ARCH/libstdc++-v3/ distclean
            PATH=$NEWPATH make $JOBS
            PATH=$NEWPATH make $JOBS install
        popd

    popd
}

setup_src

mkdir -p $DST_DIR

build_arch i686-linux-gnu i686-w64-mingw32

build_arch x86_64-linux-gnu x86_64-w64-mingw32

echo "Done!"
