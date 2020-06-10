#!/bin/bash
# com.khronos.python | make.sh

set -e
set -u

PROJECTROOT="$(cd $(dirname $0)&&pwd)"
readonly PROJECTROOT
cd "${PROJECTROOT}"

ARCH="${ARCH-$(arch)}"
if [ "${ARCH}" = arm ]; then
  ARCH=armv7
fi

VERSION="3.8.3"
PATCHVERSION="1"

export CC="${PROJECTROOT}/clang-ldid"
export AR=llvm-ar

export CFLAGS="-isysroot /usr/share/SDKs/iPhoneOS.sdk -miphoneos-version-min=7.0 -arch ${ARCH} -I/usr/local/include -I/usr/include"
export LDFLAGS="-isysroot /usr/share/SDKs/iPhoneOS.sdk -miphoneos-version-min=7.0 -arch ${ARCH} -L/usr/local/lib -L/usr/lib"

download() {
  if [ ! -r "${PROJECTROOT}/Python-${VERSION}.tar.xz" ]; then
    curl -o "${PROJECTROOT}/Python-${VERSION}.tar.xz" "https://www.python.org/ftp/python/${VERSION}/Python-${VERSION}.tar.xz"
  fi
  tar xvf "${PROJECTROOT}/Python-${VERSION}.tar.xz" -C "${BUILDROOT}"
}

init() {
  ARCH="$1"
  BUILDROOT="${PROJECTROOT}/${ARCH}"
  BUILDPYROOT="${BUILDROOT}/Python-${VERSION}"
  if [ -e "${BUILDROOT}" ]; then
    rm -rf "${BUILDROOT}"
  fi
  mkdir -p "${BUILDROOT}"
}

applyPatch() {
  for p in $(find "${PROJECTROOT}/patches/${VERSION}" -name "*.patch"); do
    patch -u -p0 -d "${BUILDROOT}" -i "$p"
  done
}

build() {
  local machine
  cd "${BUILDPYROOT}"
  if [ "${ARCH}" = arm64 ]; then
    machine="aarch64-apple-darwin"
  else
    machine="arm-apple-darwin"
  fi

  sh configure \
    --build="${machine}" \
    --prefix=/usr \
    --enable-shared \
    --disable-static \
    --enable-optimizations \
    --enable-loadable-sqlite-extensions \
    --with-signal-module \
    --enable-big-digits \
    --enable-ipv6 \
    --enable-unicode \
    --enable-unicode=ucs4 \
    --with-system-expat \
    --with-system-ffi \
    --without-ensurepip \
    --with-dtrace \
    --with-dbmloader=gdbm \
    ac_cv_func_sendfile=no \
    ac_cv_file__dev_ptmx=no \
    ac_cv_file__dev_ptc=no
  make -j3

  cd "${PROJECTROOT}"
}

bundle() {
  local destdir="${BUILDROOT}/build"
  rm -rf "${destdir}"
  mkdir -p "${destdir}"

  local sharedir="${destdir}/usr/share"
  local bindir="${destdir}/usr/bin"
  local libdir="${destdir}/usr/lib/python${VERSION}"
  local mandir="${sharedir}/man/man1"
  local licensedir="${sharedir}/licenses/python"

  cd "${BUILDPYROOT}"

  make -j3 install DESTDIR="${destdir}"

  ln -s idle3 "${bindir}/idle"
  ln -s pydoc3 "${bindir}/pydoc"
  ln -s python3 "${bindir}/python"
  ln -s python3-config "${bindir}/python-config"

  ln -s libpython "${libdir}/doc"

  unlink "${mandir}/python3.1"
  gzip "${mandir}/python3.8.1"
  ln -s python3.8.1.gz "${mandir}/python3.1.gz"
  ln -s python3.8.1.gz "${mandir}/python.1.gz"

  mkdir -p "${licensedir}"
  cp -R LICENSE "${licensedir}"

  cd "${PROJECTROOT}"
}

merge() {
  mkdir -p "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/arm64/build/." "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/armv7/build/." "${PROJECTROOT}/fat/build"

  cd "${PROJECTROOT}"

  find "fat/build" -type f |
  while read x; do
    if lipo -info "$x" >/dev/null 2>&1; then
      rm "$x"
      lipo -create "${x/fat/arm64}" "${x/fat/armv7}" -output "$x"
      if test -x "$x"; then
        ldid -S/usr/share/SDKs/entitlements.xml "$x"
      fi
    fi
  done
}

pack() {
  local ARCHS
  if [ "$1" = fat ]; then
    ARCHS="ARM64/ARMv7"
  elif [ "$1" = arm64 ]; then
    ARCHS=ARM64
  elif [ "$1" = armv7 ]; then
    ARCHS=ARMv7
  else
    echo "Unknown architecture." >&2
    exit 1
  fi
  BUILDROOT="${PROJECTROOT}/$1"
  cp -R "${PROJECTROOT}/deb/." "${BUILDROOT}/build"
  sed -e "/^Version:/s/%%VERSION%%/${VERSION}-${PATCHVERSION}/" \
      -e "/^Description:/s_%%ARCHS%%_${ARCHS}_" \
      -i -- "${BUILDROOT}/build/DEBIAN/control"
  dpkg-deb -Zgzip --root-owner-group --build "${BUILDROOT}/build" "${BUILDROOT}"
  # su -c "chown -R 0:0 ${BUILDROOT}/build"
  # dpkg-deb -Zgzip --build "${BUILDROOT}/build" "${BUILDROOT}"
}

init "${ARCH}"
download
applyPatch
build
bundle

# merge

pack "${ARCH}"
