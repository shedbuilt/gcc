#!/bin/bash
patch -Np1 -i $SHED_PATCHDIR/gcc-5.3.0-h3-cpu-default.patch
mkdir -v build
cd build
SED=sed                               \
../configure --prefix=/usr            \
             --enable-languages=c,c++ \
             --disable-multilib       \
             --disable-bootstrap      \
             --with-system-zlib
make
make DESTDIR=${SHED_FAKEROOT} install
mkdir -v ${SHED_FAKEROOT}/lib
ln -sv ../usr/bin/cpp ${SHED_FAKEROOT}/lib
ln -sv gcc ${SHED_FAKEROOT}/usr/bin/cc
install -v -dm755 ${SHED_FAKEROOT}/usr/lib/bfd-plugins
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/7.2.0/liblto_plugin.so ${SHED_FAKEROOT}/usr/lib/bfd-plugins/
mkdir -pv ${SHED_FAKEROOT}/usr/share/gdb/auto-load/usr/lib
mv -v ${SHED_FAKEROOT}/usr/lib/*gdb.py ${SHED_FAKEROOT}/usr/share/gdb/auto-load/usr/lib
