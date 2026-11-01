#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build the Xoom kernel, DTB and modules.
#   scripts/build-kernel.sh <linux-source-dir> <output-dir>
# The source is xoom-linux/linux at the commit pinned in kernel/SOURCE; the
# patches in kernel/patches are applied to it (a clean checkout is expected).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(realpath "$1")
OUT=$(realpath -m "$2")
DTB_NAME=${DTB_NAME:-tegra20-motorola-mz605}
JOBS=${JOBS:-$(nproc)}
CROSS=${CROSS_COMPILE:-arm-linux-gnueabihf-}
export ARCH=arm CROSS_COMPILE=$CROSS KBUILD_BUILD_USER=nuraxoom KBUILD_BUILD_HOST=builder
# Keep the release string to CONFIG_LOCALVERSION (no "+" for a patched tree).
export LOCALVERSION=

. "$REPO/kernel/SOURCE"
have=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)
[ "$have" = "$KERNEL_COMMIT" ] || echo "WARNING: source is $have, pinned is $KERNEL_COMMIT" >&2

mkdir -p "$OUT/build"
# Apply our patches (idempotent: skipped if already applied).
for p in "$REPO"/kernel/patches/*.patch; do
	if git -C "$SRC" apply --check "$p" 2>/dev/null; then
		git -C "$SRC" apply "$p"; echo "applied $(basename "$p")"
	elif git -C "$SRC" apply --reverse --check "$p" 2>/dev/null; then
		echo "already applied $(basename "$p")"
	else
		echo "patch does not apply: $p" >&2; exit 1
	fi
done

cp "$REPO/kernel/config-motorola-mz605.armv7" "$OUT/build/.config"
make -C "$SRC" O="$OUT/build" olddefconfig
make -C "$SRC" O="$OUT/build" -j"$JOBS" zImage modules "nvidia/$DTB_NAME.dtb"
rm -rf "$OUT/modules"
make -C "$SRC" O="$OUT/build" INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1 modules_install
KREL=$(cat "$OUT/build/include/config/kernel.release")
rm -f "$OUT/modules/lib/modules/$KREL/build" "$OUT/modules/lib/modules/$KREL/source"

cp "$OUT/build/arch/arm/boot/zImage" "$OUT/zImage"
cp "$OUT/build/arch/arm/boot/dts/nvidia/$DTB_NAME.dtb" "$OUT/$DTB_NAME.dtb"
cp "$OUT/build/.config" "$OUT/kernel.config"
echo "$KREL" > "$OUT/kernel.release"
echo "kernel $KREL -> $OUT"
