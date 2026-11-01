#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# build-boot.sh ZIMAGE DTB BUSYBOX_STATIC VERSION OUT.img
# Packs xoomboot (BusyBox + init) and the kernel+appended DTB into an
# Android v0 boot image for the Motorola Xoom bootloader.
# CMDLINE in the environment overrides the kernel command line.
set -eu
ZIMAGE=$1 DTB=$2 BUSYBOX=$3 VERSION=$4 OUT=$5
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

mkdir -p "$W"/ramdisk/bin "$W"/ramdisk/dev "$W"/ramdisk/proc "$W"/ramdisk/sys \
         "$W"/ramdisk/run "$W"/ramdisk/tmp "$W"/ramdisk/newroot "$W"/ramdisk/android
install -m755 "$BUSYBOX" "$W"/ramdisk/bin/busybox
ln -s busybox "$W"/ramdisk/bin/sh
sed "s/@VERSION@/$VERSION/" "$HERE"/boot/init > "$W"/ramdisk/init
chmod 755 "$W"/ramdisk/init
# Static device nodes so early messages work before devtmpfs is mounted.
if [ "$(id -u)" = 0 ]; then
	mknod -m 600 "$W"/ramdisk/dev/console c 5 1
	mknod -m 666 "$W"/ramdisk/dev/null c 1 3
fi
(cd "$W"/ramdisk && find . | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 --reproducible) \
	| gzip -9n > "$W"/ramdisk.cpio.gz

cat "$ZIMAGE" "$DTB" > "$W"/zImage-dtb
python3 "$HERE"/tools/mkbootimg.py \
	--kernel "$W"/zImage-dtb --ramdisk "$W"/ramdisk.cpio.gz \
	--base 0x10000000 --kernel-offset 0x00008000 --ramdisk-offset 0x01000000 \
	--second-offset 0x00f00000 --tags-offset 0x00000100 --pagesize 2048 \
	--board xoomboot \
	--cmdline "${CMDLINE:-console=tty1 fbcon=font:TER16x32 loglevel=4 rdinit=/init}" \
	-o "$OUT"
size=$(wc -c < "$OUT")
[ "$size" -lt 8388608 ] || { echo "boot image $size bytes > 8 MiB boot partition" >&2; exit 1; }
echo "$OUT: $size bytes"
