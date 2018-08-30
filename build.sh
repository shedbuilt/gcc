#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}
# Apply default architecture patch
case "$SHED_CPU_CORE" in
    cortex-a7)
        if [ "$SHED_CPU_FEATURES" == 'neon-vfpv4' ]; then
            patch -Np1 -i "${SHED_PKG_PATCH_DIR}/gcc-8.2.0-cortex-a7-neon-vfpv4.patch" || exit 1
        else
            echo "Unsupported CPU features: $SHED_CPU_FEATURES"
            exit 1
        fi
        ;;
    cortex-a53)
        if [ "$SHED_CPU_FEATURES" == 'crypto' ]; then
            patch -Np1 -i "${SHED_PKG_PATCH_DIR}/gcc-8.2.0-cortex-a53-crypto.patch" || exit 1
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

# Ensure 64-bit libraries are installed in /lib
if [[ $SHED_BUILD_TARGET =~ ^aarch64-.* ]]; then
    sed -i '/mabi.lp64=/s/lib64/lib/' gcc/config/aarch64/t-aarch64-linux || exit 1
    SHEDPKG_GCC_CONFIG_HEADER='gcc/config/aarch64/aarch64-linux.h'
else
    SHEDPKG_GCC_CONFIG_HEADER='gcc/config/arm/linux-eabi.h'
fi

# Toolchain build configuration
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
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

    if [ "$SHED_BUILD_HOST" != "$SHED_NATIVE_TARGET" ] && [ "$SHED_BUILD_TARGET" == "$SHED_NATIVE_TARGET" ]; then
        cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $(${SHED_BUILD_HOST}-gcc -print-libgcc-file-name)`/include-fixed/limits.h
    fi
    # Modify the config header to look for glibc in our toolchain folder
    sed -i 's@/lib/ld@/tools&@g' "$SHEDPKG_GCC_CONFIG_HEADER" || exit 1
    echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> "$SHEDPKG_GCC_CONFIG_HEADER"
fi

# Configure
mkdir -v build
cd build
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    if [ "$SHED_BUILD_HOST" != "$SHED_NATIVE_TARGET" ] && [ "$SHED_BUILD_TARGET" == "$SHED_NATIVE_TARGET" ]; then
        CC=${SHED_BUILD_HOST}-gcc                                       \
        CXX=${SHED_BUILD_HOST}-g++                                      \
        AR=${SHED_BUILD_HOST}-ar                                        \
        RANLIB=${SHED_BUILD_HOST}-ranlib                                \
        ../configure --prefix=/tools                                \
                     --with-local-prefix=/tools                     \
                     --with-native-system-header-dir=/tools/include \
                     --enable-languages=c,c++                       \
                     --disable-libstdcxx-pch                        \
                     --disable-multilib                             \
                     --disable-bootstrap                            \
                     --disable-libgomp || exit 1
    elif [ "$SHED_BUILD_TARGET" != "$SHED_NATIVE_TARGET" ]; then
        ../configure --prefix=/tools                                \
                     --target=$SHED_BUILD_TARGET                    \
                     --with-glibc-version=2.11                      \
                     --with-sysroot="$SHED_INSTALL_ROOT"            \
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
        echo "Unsupported host and/or target for toolchain build"
        exit 1
    fi
else
    SED=sed                               \
    ../configure --prefix=/usr            \
                 --enable-languages=c,c++ \
                 --disable-multilib       \
                 --disable-bootstrap      \
                 --disable-libmpx         \
                 --with-system-zlib || exit 1
fi

# Build and Install
make -j $SHED_NUM_JOBS &&
make DESTDIR="$SHED_FAKE_ROOT" install || exit 1

# Rearrange
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    if [ "$SHED_BUILD_HOST" != "$SHED_NATIVE_TARGET" ] && [ "$SHED_BUILD_TARGET" == "$SHED_NATIVE_TARGET" ]; then
        ln -sv gcc "${SHED_FAKE_ROOT}/tools/bin/cc"
    fi
else
    mkdir -v "${SHED_FAKE_ROOT}/lib" &&
    ln -sv ../usr/bin/cpp "${SHED_FAKE_ROOT}/lib" &&
    ln -sv gcc "${SHED_FAKE_ROOT}/usr/bin/cc" &&
    install -v -dm755 "${SHED_FAKE_ROOT}/usr/lib/bfd-plugins" &&
    ln -sfv ../../libexec/gcc/${SHED_BUILD_TARGET}/${SHED_PKG_VERSION}/liblto_plugin.so "${SHED_FAKE_ROOT}/usr/lib/bfd-plugins/" &&
    mkdir -pv "${SHED_FAKE_ROOT}/usr/share/gdb/auto-load/usr/lib" &&
    mv -v "${SHED_FAKE_ROOT}/usr/lib"/*gdb.py "${SHED_FAKE_ROOT}/usr/share/gdb/auto-load/usr/lib"
fi
