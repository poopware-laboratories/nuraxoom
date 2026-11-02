#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Build grate's Mesa (Gallium "grate" driver for the Tegra 2 GPU) with the
# NuraXoom patches, natively on Alpine armv7 (the tablet, or an armv7
# chroot under qemu with QEMU_CPU=cortex-a9,neon=off,vfp-d32=off):
#   doas apk add build-base git meson ninja python3 py3-mako py3-packaging \
#       flex bison pkgconf libdrm-dev expat-dev zlib-dev zstd-dev wayland-dev \
#       wayland-protocols libx11-dev libxext-dev libxfixes-dev \
#       libxshmfence-dev libxxf86vm-dev libxrandr-dev libxcb-dev \
#       libxdamage-dev glslang
#   sh build.sh [OUT.tar.gz]
# Installs into /opt/mesa-grate (next to Alpine's Mesa, which isn't
# replaced) and packs that as OUT (default ./mesa-grate-armv7.tar.gz).
# MESA_SRC=<dir> builds from an existing checkout of $PIN instead of
# fetching it.
# Tegra 2 has VFPv3-D16 and no NEON: -mfpu=vfpv3-d16 is required.
set -eu
PIN=4621b88ee2e0f2cdbcb76d9f14eda4922c0123f4   # grate-driver/mesa 22.2.4
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$PWD/mesa-grate-armv7.tar.gz}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ -n "${MESA_SRC:-}" ]; then
	mkdir "$W/src"
	(cd "$MESA_SRC" && git archive "$PIN") | tar -xf - -C "$W/src"
else
	git init -q "$W/src"
	git -C "$W/src" fetch -q --depth 1 https://github.com/grate-driver/mesa "$PIN"
	git -C "$W/src" checkout -q FETCH_HEAD
	[ "$(git -C "$W/src" rev-parse HEAD)" = "$PIN" ]
fi
cd "$W/src"
for p in "$HERE"/0*.patch; do
	patch -p1 < "$p"
done

FLAGS="-O2 -mcpu=cortex-a9 -mfpu=vfpv3-d16 -mfloat-abi=hard"
CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" meson setup "$W/build" \
	--prefix=/opt/mesa-grate --buildtype=release -Db_ndebug=true \
	-Dgallium-drivers=grate -Dvulkan-drivers= -Dplatforms=x11,wayland \
	-Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled \
	-Dopengl=true -Dglx=dri -Dllvm=disabled -Dshared-glapi=enabled \
	-Dgallium-vdpau=disabled -Dgallium-va=disabled -Dgallium-xa=disabled \
	-Dgallium-nine=false -Dgallium-opencl=disabled -Dvalgrind=disabled \
	-Dlibunwind=disabled -Dzstd=enabled -Dbuild-tests=false
ninja -C "$W/build"
DESTDIR="$W/root" ninja -C "$W/build" install >/dev/null

# Refuse binaries built for NEON or VFP registers d16-d31.
for f in "$W"/root/opt/mesa-grate/lib/*.so.*.* "$W"/root/opt/mesa-grate/lib/dri/*.so; do
	if readelf -A "$f" | grep -q Tag_Advanced_SIMD_arch ||
	   ! readelf -A "$f" | grep -q "Tag_FP_arch: VFPv3-D16"; then
		echo "ERROR: $f is not VFPv3-D16 without NEON, it would SIGILL on Tegra 2" >&2
		exit 1
	fi
done
tar -C "$W/root" -czf "$OUT" opt/mesa-grate
sha256sum "$OUT"
