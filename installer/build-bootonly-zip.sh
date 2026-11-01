#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# build-bootonly-zip.sh NAME BOOT.img BUSYBOX_STATIC OUT.zip
# TWRP zip that only writes BOOT.img (for testing kernels against an install).
set -eu
NAME=$1 BOOTIMG=$2 BUSYBOX=$3 OUT=$(realpath -m "$4")
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W"/META-INF/com/google/android "$W"/nuraxoom
cp "$HERE"/installer/bootonly-update-binary "$W"/META-INF/com/google/android/update-binary
cp "$HERE"/installer/updater-script "$W"/META-INF/com/google/android/updater-script
install -m755 "$BUSYBOX" "$W"/nuraxoom/busybox
cp "$BOOTIMG" "$W"/nuraxoom/boot.img
echo "$NAME" > "$W"/nuraxoom/NAME
(cd "$W"/nuraxoom && sha256sum boot.img > boot.img.sha256)
rm -f "$OUT"
(cd "$W" && zip -q -X -r "$OUT" META-INF nuraxoom)
ls -l "$OUT"
