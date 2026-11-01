#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# build-zips.sh VERSION BOOT.img ROOTFS.tar.gz BUSYBOX_STATIC OUTDIR
# Produces the TWRP install zip and the boot-restore zip.
set -eu
VERSION=$1 BOOTIMG=$2 ROOTFS=$3 BUSYBOX=$4 OUTDIR=$5
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
M=$W/install/META-INF/com/google/android
P=$W/install/nuraxoom
mkdir -p "$M" "$P"
sed "s/@VERSION@/$VERSION/" "$HERE"/installer/update-binary > "$M"/update-binary
cp "$HERE"/installer/updater-script "$M"/updater-script
install -m755 "$BUSYBOX" "$P"/busybox
cp "$BOOTIMG" "$P"/boot.img
cp "$ROOTFS" "$P"/nura-rootfs.tar.gz
cp "$HERE"/installer/wifi.txt.example "$P"/wifi.txt.example
echo "$VERSION" > "$P"/VERSION
(cd "$P" && sha256sum boot.img nura-rootfs.tar.gz > SHA256SUMS)
Z=$OUTDIR/NuraXoom-$VERSION-wingray-twrp.zip
rm -f "$Z"
# Store the big payload uncompressed so TWRP can stream it quickly.
(cd "$W"/install && zip -q -X -r "$Z" META-INF nuraxoom -x nuraxoom/nura-rootfs.tar.gz \
	&& zip -q -X -0 "$Z" nuraxoom/nura-rootfs.tar.gz)

R=$W/restore
mkdir -p "$R"/META-INF/com/google/android "$R"/nuraxoom
cp "$HERE"/installer/restore-update-binary "$R"/META-INF/com/google/android/update-binary
cp "$HERE"/installer/updater-script "$R"/META-INF/com/google/android/updater-script
install -m755 "$BUSYBOX" "$R"/nuraxoom/busybox
RZ=$OUTDIR/NuraXoom-restore-boot.zip
rm -f "$RZ"
(cd "$R" && zip -q -X -r "$RZ" META-INF nuraxoom)

C=$W/crashlog
mkdir -p "$C"/META-INF/com/google/android "$C"/nuraxoom
cp "$HERE"/installer/crashlog-update-binary "$C"/META-INF/com/google/android/update-binary
cp "$HERE"/installer/updater-script "$C"/META-INF/com/google/android/updater-script
install -m755 "$BUSYBOX" "$C"/nuraxoom/busybox
CZ=$OUTDIR/NuraXoom-save-crashlog.zip
rm -f "$CZ"
(cd "$C" && zip -q -X -r "$CZ" META-INF nuraxoom)
(cd "$OUTDIR" && sha256sum "$(basename "$Z")" "$(basename "$RZ")" "$(basename "$CZ")" > SHA256SUMS)
ls -l "$Z" "$RZ" "$CZ"
