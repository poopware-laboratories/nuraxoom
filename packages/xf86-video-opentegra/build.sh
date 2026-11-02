#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Build prebuilt/opentegra_drv.so natively on Alpine armv7 (the tablet itself
# running NuraXoom works):
#   doas apk add build-base autoconf automake libtool pkgconf flex bison \
#       util-macros xorgproto xorg-server-dev libdrm-dev pixman-dev eudev-dev \
#       lz4-dev libjpeg-turbo-dev libpng-dev curl
#   sh build.sh [OUTDIR]
# OPENTEGRA_SRC=<dir> builds from an existing checkout of $PIN instead of
# downloading it.
# Tegra 2 has VFPv3-D16 and no NEON: -mfpu=vfpv3-d16 is required. The old zig
# build used d16-d31 and Xorg died with SIGILL once compositing was used.
set -eu
PIN=9be4b4aa7c81b9b43496e8621954a0f4b343f3b1
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "${1:-$HERE/prebuilt}" && cd "${1:-$HERE/prebuilt}" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ -n "${OPENTEGRA_SRC:-}" ]; then
	mkdir "$W/xf86-video-opentegra-$PIN"
	(cd "$OPENTEGRA_SRC" && tar --exclude=.git -cf - .) | tar -xf - -C "$W/xf86-video-opentegra-$PIN"
else
	curl -fsSL "https://github.com/grate-driver/xf86-video-opentegra/archive/$PIN.tar.gz" -o "$W/src.tar.gz"
	echo "17ef37e4457a9c9e1659660809b9ee000745c171fbc675fc413603799747e7ec  $W/src.tar.gz" | sha256sum -c
	tar -xzf "$W/src.tar.gz" -C "$W"
fi
cd "$W/xf86-video-opentegra-$PIN"
for p in "$HERE"/0*.patch; do
	patch -p1 < "$p"
done
NOCONFIGURE=1 ./autogen.sh
./configure --prefix=/usr \
	CFLAGS="-O2 -g -mcpu=cortex-a9 -mfpu=vfpv3-d16 -mfloat-abi=hard -fno-omit-frame-pointer"
make -j"$(nproc)"
# Refuse a binary that uses VFP registers d16-d31 or NEON. Check before
# stripping: without the $a/$t mapping symbols objdump decodes Thumb as ARM.
if objdump -d src/.libs/opentegra_drv.so | grep -qE '\bd(1[6-9]|2[0-9]|3[01])\b|\sq[0-9]+\b'; then
	echo "ERROR: binary uses d16-d31/NEON, it would SIGILL on Tegra 2" >&2
	exit 1
fi
strip -o "$OUT/opentegra_drv.so" src/.libs/opentegra_drv.so
sha256sum "$OUT/opentegra_drv.so"
