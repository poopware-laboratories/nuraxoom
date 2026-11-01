#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# build-overlay-zip.sh NAME BUSYBOX_STATIC OUT.zip PATH...
# BOOTIMG=boot.img in the environment also puts that boot image in the zip.
# EXTRA_ROOT=dir adds every file under dir too (private, never in the repo:
# dev SSH key, Wi-Fi network); modes are kept (directories too: TWRP's tar would
# otherwise create new ones with its own umask, which sshd StrictModes rejects),
# owner becomes root.
# TWRP zip that drops device-package files (PATH relative to
# device/motorola-wingray/rootfs, e.g. usr/libexec/nuraxoom/console-session)
# over an existing /data/linux/nura, root-owned, modes as in the repo.
set -eu
NAME=$1 BUSYBOX=$2 OUT=$(realpath -m "$3")
shift 3
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W"/META-INF/com/google/android "$W"/nuraxoom
cp "$HERE"/installer/overlay-update-binary "$W"/META-INF/com/google/android/update-binary
cp "$HERE"/installer/updater-script "$W"/META-INF/com/google/android/updater-script
install -m755 "$BUSYBOX" "$W"/nuraxoom/busybox
echo "$NAME" > "$W"/nuraxoom/NAME
[ -z "${BOOTIMG:-}" ] || cp "$BOOTIMG" "$W"/nuraxoom/boot.img
tar --owner=0 --group=0 --numeric-owner -C "$HERE"/device/motorola-wingray/rootfs \
	-cf "$W"/nuraxoom/overlay.tar "$@"
[ -z "${EXTRA_ROOT:-}" ] || tar --owner=0 --group=0 --numeric-owner -C "$EXTRA_ROOT" \
	-rf "$W"/nuraxoom/overlay.tar --no-recursion $(cd "$EXTRA_ROOT" && find . -mindepth 1 | sort)
(cd "$W"/nuraxoom && sha256sum overlay.tar $([ -f boot.img ] && echo boot.img) > SHA256SUMS)
rm -f "$OUT"
(cd "$W" && zip -q -X -r "$OUT" META-INF nuraxoom)
ls -l "$OUT"
