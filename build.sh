#!/bin/bash
# Apply default architecture patch
case "$SHED_HWCONFIG" in
    orangepi-one|orangepi-pc)
        patch -Np1 -i "$SHED_PATCHDIR/gcc-7.2.0-h3-cpu-default.patch"
        ;;
    aml-s905x-cc)
        patch -Np1 -i "$SHED_PATCHDIR/gcc-7.2.0-s905x-cpu-default.patch"
        ;;
    *)
        echo "Unsupported config: $SHED_HWCONFIG"
        exit 1
        ;;
esac
if [ "$SHED_BUILDMODE" == 'toolchain' ]; then
    # Build the required GMP, MPFR and MPC packages
    # HACK: Until shedmake supports multiple source files, this will
    #       have to be done at build time.
    { wget http://www.mpfr.org/mpfr-4.0.0/mpfr-4.0.0.tar.xz && \
      tar -xf mpfr-4.0.0.tar.xz && \
      mv -v mpfr-4.0.0 mpfr; } || exit 1
    { wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz && \
      tar -xf gmp-6.1.2.tar.xz && \
      mv -v gmp-6.1.2 gmp; } || exit 1
    { wget https://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz && \
      tar -xf mpc-1.0.3.tar.gz && \
      mv -v mpc-1.0.3 mpc; } || exit 1

    if [ "$SHED_HOST" == 'toolchain' ] && [ "$SHED_TARGET" == 'native' ]; then
        cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $(${SHED_TOOLCHAIN_TARGET}-gcc -print-libgcc-file-name)`/include-fixed/limits.h
    fi
    for file in gcc/config/arm/linux-eabi.h
    do
        cp -uv $file{,.orig}
        sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
            -e 's@/usr@/tools@g' $file.orig > $file
        echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
        touch $file.orig
    done
fi
mkdir -v build
cd build
case "$SHED_BUILDMODE" in
    toolchain)
        if [ "$SHED_HOST" == 'toolchain' ] && [ "$SHED_TARGET" == 'native' ]; then
            CC=${SHED_TOOLCHAIN_TARGET}-gcc                                       \
            CXX=${SHED_TOOLCHAIN_TARGET}-g++                                      \
            AR=${SHED_TOOLCHAIN_TARGET}-ar                                        \
            RANLIB=${SHED_TOOLCHAIN_TARGET}-ranlib                                \
            ../configure --prefix=/tools                                \
                         --with-local-prefix=/tools                     \
                         --with-native-system-header-dir=/tools/include \
                         --enable-languages=c,c++                       \
                         --disable-libstdcxx-pch                        \
                         --disable-multilib                             \
                         --disable-bootstrap                            \
                         --disable-libgomp || exit 1
        elif [ "$SHED_TARGET" == 'toolchain' ]; then
            ../configure --prefix=/tools                                \
                         --target=$SHED_TOOLCHAIN_TARGET                \
                         --with-glibc-version=2.11                      \
                         --with-sysroot="$SHED_INSTALLROOT"             \
                         --with-newlib                                  \
                         --without-headers                              \
                         --with-local-prefix=/tools                     \
                         --with-native-system-header-dir=/tools/include \
                         --disable-nls                                  \
                         --disable-shared                               \
                         --disable-multilib                             \
                         --disable-decimal-float                        \
                         --disable-threads                              \
                         --disable-libatomic                            \
                         --disable-libgomp                              \
                         --disable-libmpx                               \
                         --disable-libquadmath                          \
                         --disable-libssp                               \
                         --disable-libvtv                               \
                         --disable-libstdcxx                            \
                         --enable-languages=c,c++ || exit 1
        else
            echo "Unsupported build options for toolchain."
            exit 1
        fi
        ;;
    *)
        SED=sed                               \
        ../configure --prefix=/usr            \
                     --enable-languages=c,c++ \
                     --disable-multilib       \
                     --disable-bootstrap      \
                     --with-system-zlib || exit 1
        ;;
esac
# GCC reportedly has issues with parallel make
make -j 1 || exit 1
make DESTDIR="$SHED_FAKEROOT" install || exit 1

case "$SHED_BUILDMODE" in
    toolchain)
        if [ "$SHED_HOST" == 'toolchain' ] && [ "$SHED_TARGET" == 'native' ]; then
            ln -sv gcc "${SHED_FAKEROOT}/tools/bin/cc"
        fi
        ;;
    *)
        mkdir -v "${SHED_FAKEROOT}/lib"
        ln -sv ../usr/bin/cpp "${SHED_FAKEROOT}/lib"
        ln -sv gcc "${SHED_FAKEROOT}/usr/bin/cc"
        install -v -dm755 "${SHED_FAKEROOT}/usr/lib/bfd-plugins"
        ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/7.2.0/liblto_plugin.so "${SHED_FAKEROOT}/usr/lib/bfd-plugins/"
        mkdir -pv "${SHED_FAKEROOT}/usr/share/gdb/auto-load/usr/lib"
        mv -v "${SHED_FAKEROOT}/usr/lib"/*gdb.py "${SHED_FAKEROOT}/usr/share/gdb/auto-load/usr/lib"
        ;;
esac
