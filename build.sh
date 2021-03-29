#!/bin/sh

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

NDK=`which ndk-build`
NDK=`dirname $NDK`
if [ $IS_LINUX ]; then
  NDK=`readlink -f $NDK`
fi

export CLANG=1

if [ ! $ARCHS ]; then
  ARCHS='armeabi armeabi-v7a arm64-v8a x86 x86_64'
fi

for ARCH in $ARCHS; do

cd $BUILDDIR

GCCPREFIX="`./setCrossEnvironment-$ARCH.sh sh -c 'basename $STRIP | sed s/-strip//'`"
echo "ARCH $ARCH GCCPREFIX $GCCPREFIX"

mkdir -p $ARCH
cd $BUILDDIR/$ARCH

# =========== libandroid_support.a ===========

[ -e libandroid_support.a ] || {
	mkdir -p android_support
	cd android_support
	ln -sf $NDK/sources/android/support jni

	#ndk-build -j$NCPU APP_ABI=$ARCH APP_MODULES=android_support LIBCXX_FORCE_REBUILD=true CLANG=1 || exit 1
	#cp -f obj/local/$ARCH/libandroid_support.a ../
	ln -sf $NDK/sources/cxx-stl/llvm-libc++/libs/$ARCH/libandroid_support.a ../

} || exit 1

# =========== libicuuc ===========

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

	env CFLAGS="-I$NDK/sources/android/support/include -frtti -fexceptions" \
		LDFLAGS="-frtti -fexceptions -L$BUILDDIR/$ARCH/lib" \
		LIBS="-L$BUILDDIR/$ARCH -landroid_support `$BUILDDIR/setCrossEnvironment-$ARCH.sh sh -c 'echo $LDFLAGS'`" \
		env ac_cv_func_strtod_l=no \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/../../ \
		--with-library-suffix=$LIBSUFFIX \
		--with-cross-build=`pwd`/cross \
		$libtype \
		--with-data-packaging=library \
		|| exit 1

#		ICULEHB_CFLAGS="-I$BUILDDIR/$ARCH/include" \
#		ICULEHB_LIBS="-licu-le-hb" \
#		--enable-layoutex \

	sed -i.tmp 's/.$(SO_TARGET_VERSION_MAJOR)//' icudefs.mk || exit 1
	sed -i.tmp 's/$(PKGDATA_VERSIONING) -e/-e/'  data/Makefile || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU VERBOSE=1 || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	for f in libicudata$LIBSUFFIX libicutest$LIBSUFFIX libicui18n$LIBSUFFIX libicuio$LIBSUFFIX libicutu$LIBSUFFIX libicuuc$LIBSUFFIX; do
		if [ $SHARED_ICU ]; then
			cp -f -H ../../lib/$f.so ../../
		else
			cp -f ../../lib/$f.a ../../
		fi
		#$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		#	sh -c '$STRIP'" ../../$f.so"
	done

} || exit 1


done # for ARCH in ...

exit 0
