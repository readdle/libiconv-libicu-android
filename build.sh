#!/bin/bash

set -x

export BUILDDIR=`pwd`

if uname -s | grep -i 'linux' &> /dev/null; then
   IS_LINUX=1
fi

if [ $IS_LINUX ]; then
   NCPU=`cat /proc/cpuinfo | grep -c -i processor`
else
   NCPU=8
fi

if uname -s | grep -i "linux" > /dev/null ; then
    MYARCH=linux-$(arch)
elif uname -s | grep -i "darwin" > /dev/null ; then
    MYARCH=darwin-x86_64
elif uname -s | grep -i "windows" > /dev/null ; then
    MYARCH=windows-x86_64
fi

NDK=`which ndk-build`
NDK=`dirname $NDK`
if [ $IS_LINUX ]; then
  NDK=`readlink -f $NDK`
fi

export CLANG=1

if [ ! $ARCHS ]; then
  ARCHS='armeabi-v7a arm64-v8a x86 x86_64'
fi

declare -A TARGETS
TARGETS=(["armeabi-v7a"]="armv7a-linux-androideabi" ["arm64-v8a"]="aarch64-linux-android" ["x86"]="i686-linux-android" ["x86_64"]="x86_64-linux-android")

for ARCH in $ARCHS
do
    cd $BUILDDIR

    mkdir -p $ARCH
    cd $BUILDDIR/$ARCH

    [ -e libicuuc$LIBSUFFIX.a ] || [ -e libicuuc$LIBSUFFIX.so ] || {

        rm -rf icu

        tar xvf ../icu4c-68_2-src.tgz

        # The ENVVAR LIBSUFFIX should add the suffix only to the libname and not to the symbols.
        # ToDo: Find the right way in Swift to refer to an alternative library with symbol prefixing or any other method to
        # remove this.
        if [ $LIBSUFFIX ]; then
            patch -p0 < ../patches/icu_suffix_only_on_libname.patch
        fi

        cd icu/source

        cp -f $BUILDDIR/config.sub .
        cp -f $BUILDDIR/config.guess .

        [ -d cross ] || {
            mkdir cross
            cd cross
            ../configure || exit 1
            make -j$NCPU VERBOSE=1 || exit 1
            cd ..
        } || exit 1

        if [ $SHARED_ICU ]; then
            libtype='--enable-shared --disable-static'
        else
            libtype='--enable-static --disable-shared'
        fi

        TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/$MYARCH
        API=21
        TARGET=${TARGETS[$ARCH]}

        export AR=$TOOLCHAIN/bin/llvm-ar
        export CC=$TOOLCHAIN/bin/$TARGET$API-clang
        export AS=$CC
        export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
        export LD=$TOOLCHAIN/bin/ld
        export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
        export STRIP=$TOOLCHAIN/bin/llvm-strip

        ./configure \
            --host=$TARGET \
            --prefix=`pwd`/../../ \
            --disable-layoutex \
            --with-library-suffix=$LIBSUFFIX \
            --with-cross-build=`pwd`/cross \
            $libtype \
            --with-data-packaging=library \
            || exit 1

        sed -i.tmp 's/.$(SO_TARGET_VERSION_MAJOR)//' icudefs.mk || exit 1
        sed -i.tmp 's/$(PKGDATA_VERSIONING) -e/-e/'  data/Makefile || exit 1

        env PATH=`pwd`:$PATH \
            make -j$NCPU VERBOSE=1 || exit 1

        env PATH=`pwd`:$PATH \
            make V=1 install || exit 1

	unset AR CC AS CXX LD RANLIB STRIP

        for f in libicudata$LIBSUFFIX libicutest$LIBSUFFIX libicui18n$LIBSUFFIX libicuio$LIBSUFFIX libicutu$LIBSUFFIX libicuuc$LIBSUFFIX; do
            if [ $SHARED_ICU ]; then
                cp -f -H ../../lib/$f.so ../../
            else
                cp -f ../../lib/$f.a ../../
            fi
        done

    } || exit 1


done # for ARCH in ...

exit 0
