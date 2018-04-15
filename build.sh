#!/bin/bash
# Apply default architecture patch
case "$SHED_CPU_CORE" in
    cortex-a7)
        if [ "$SHED_CPU_FEATURES" == 'neon-vfpv4' ]; then
            patch -Np1 -i "$SHED_PKG_PATCH_DIR/gcc-7.3.0-cortex-a7-neon-vfpv4.patch"
        else
            echo "Unsupported CPU features: $SHED_CPU_FEATURES"
            exit 1
        fi
        ;;
    cortex-a53)
        if [ "$SHED_CPU_FEATURES" == 'crypto' ]; then
            patch -Np1 -i "$SHED_PKG_PATCH_DIR/gcc-7.3.0-cortex-a53-crypto.patch"
        else
            echo "Unsupported CPU features: $SHED_CPU_FEATURES"
            exit 1
        fi
        ;;
    *)
        echo "Unsupported CPU core: $SHED_CPU_CORE"
        exit 1
        ;;
esac

# Ensure 64-bit libraries are install in /lib
if [[ $SHED_TOOLCHAIN_TARGET =~ ^aarch64-.* ]]; then
    sed -i '/mabi.lp64=/s/lib64/lib/' gcc/config/aarch64/t-aarch64-linux || exit 1
    SHEDPKG_GCC_CONFIG_HEADER='gcc/config/aarch64/aarch64-linux.h'
else
    SHEDPKG_GCC_CONFIG_HEADER='gcc/config/arm/linux-eabi.h'
fi

# Toolchain build configuration
if [ "$SHED_BUILD_MODE" == 'toolchain' ]; then
    # Build the required GMP, MPFR and MPC packages
    # HACK: Until shedmake supports multiple source files, this will
    #       have to be done at build time.
    { wget http://www.mpfr.org/mpfr-4.0.1/mpfr-4.0.1.tar.xz &&
      tar -xf mpfr-4.0.1.tar.xz &&
      mv -v mpfr-4.0.1 mpfr; } || exit 1
    { wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz &&
      tar -xf gmp-6.1.2.tar.xz &&
      mv -v gmp-6.1.2 gmp; } || exit 1
    { wget https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz &&
      tar -xf mpc-1.1.0.tar.gz &&
      mv -v mpc-1.1.0 mpc; } || exit 1

    if [ "$SHED_BUILD_HOST" == 'toolchain' ] && [ "$SHED_BUILD_TARGET" == 'native' ]; then
        cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $(${SHED_TOOLCHAIN_TARGET}-gcc -print-libgcc-file-name)`/include-fixed/limits.h
    fi
    # Modify the config header to look for glibc in our toolchain folder
    sed -i 's@/lib/ld@/tools&@g' "$SHEDPKG_GCC_CONFIG_HEADER" || exit 1
    echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> "$SHEDPKG_GCC_CONFIG_HEADER" 
fi

mkdir -v build
cd build
case "$SHED_BUILD_MODE" in
    toolchain)
        if [ "$SHED_BUILD_HOST" == 'toolchain' ] && [ "$SHED_BUILD_TARGET" == 'native' ]; then
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
        elif [ "$SHED_BUILD_TARGET" == 'toolchain' ]; then
            ../configure --prefix=/tools                                \
                         --target=$SHED_TOOLCHAIN_TARGET                \
                         --with-glibc-version=2.11                      \
                         --with-sysroot="$SHED_INSTALL_ROOT"             \
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

make -j $SHED_NUM_JOBS &&
make DESTDIR="$SHED_FAKE_ROOT" install || exit 1

case "$SHED_BUILD_MODE" in
    toolchain)
        if [ "$SHED_BUILD_HOST" == 'toolchain' ] && [ "$SHED_BUILD_TARGET" == 'native' ]; then
            ln -sv gcc "${SHED_FAKE_ROOT}/tools/bin/cc"
        fi
        ;;
    *)
        mkdir -v "${SHED_FAKE_ROOT}/lib" &&
        ln -sv ../usr/bin/cpp "${SHED_FAKE_ROOT}/lib" &&
        ln -sv gcc "${SHED_FAKE_ROOT}/usr/bin/cc" &&
        install -v -dm755 "${SHED_FAKE_ROOT}/usr/lib/bfd-plugins" &&
        ln -sfv ../../libexec/gcc/${SHED_NATIVE_TARGET}/7.3.0/liblto_plugin.so "${SHED_FAKE_ROOT}/usr/lib/bfd-plugins/" &&
        mkdir -pv "${SHED_FAKE_ROOT}/usr/share/gdb/auto-load/usr/lib" &&
        mv -v "${SHED_FAKE_ROOT}/usr/lib"/*gdb.py "${SHED_FAKE_ROOT}/usr/share/gdb/auto-load/usr/lib"
        ;;
esac
