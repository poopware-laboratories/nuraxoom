#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the Nura root filesystem for /data/linux/nura on the Xoom, from the
# Nura (postmarketOS) and Alpine edge repositories.
#
#   build-nura-rootfs.sh MODULES_DIR FIRMWARE_DIR OUT.tar.gz [OPENTEGRA_DRV.so]
#
# MODULES_DIR   output of scripts/build-kernel.sh (contains lib/modules/<release>)
# FIRMWARE_DIR  output of scripts/fetch-firmware.sh (stock-wifi-nvram.txt)
#
# NURAXOOM_UI   desktops to install: xfce lxqt mate sxmo phosh (space or comma
#               separated) or "all". Default: xfce.
# NURAXOOM_SESSION  what starts on boot: one of the installed desktops, or
#               console. Default: the first desktop in NURAXOOM_UI.
#
# Runs as root on an armv7-capable host: an ARM host, or x86/arm64 with
# qemu-arm registered in binfmt_misc with the F flag (package scripts run in
# the armv7 chroot). Needs network.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (needs to preserve ownership)" >&2; exit 1; }
MODS=$1 FW=$2 OUT=$3 XDRV=${4:-}
HERE=$(cd "$(dirname "$0")/.." && pwd)
DEV=$HERE/device/motorola-wingray
R=$(mktemp -d /var/tmp/nura-rootfs.XXXXXX)
W=$(mktemp -d /var/tmp/nura-apk.XXXXXX)
cleanup() {
	umount "$R"/dev "$R"/proc 2>/dev/null || true
	rm -rf "$R" "$W"
}
trap cleanup EXIT
USER_NAME=user
USER_UID=10000
# Default password for "user" (doas, console login). Change it: passwd
USER_PASS=${NURA_PASSWORD:-147147}
# Desktops in the image; switch on the device with: doas nuraxoom-session <name>
UI=$(echo "${NURAXOOM_UI:-xfce}" | tr ',' ' ')
[ "$UI" = all ] && UI="xfce lxqt mate sxmo phosh"
for u in $UI; do
	[ -f "$HERE/rootfs/ui/$u.txt" ] || { echo "unknown desktop: $u" >&2; exit 1; }
done
# What starts on boot: a desktop (through tinydm) or console (tty1 + fbkeyboard).
SESSION=${NURAXOOM_SESSION:-${UI%% *}}
case " $UI console " in *" $SESSION "*) ;; *) echo "NURAXOOM_SESSION=$SESSION is not in NURAXOOM_UI" >&2; exit 1 ;; esac
has_ui() { case " $UI " in *" $1 "*) return 0 ;; esac; return 1; }
# testing: Nura's networkmanager UI package needs routewrangler from there.
REPOS="https://mirror.nura.eco/postmarketos/master
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing"
ALPINE=https://dl-cdn.alpinelinux.org/alpine/edge/main

[ -f "$FW/stock-wifi-nvram.txt" ] || { echo "missing $FW/stock-wifi-nvram.txt (run scripts/fetch-firmware.sh)" >&2; exit 1; }

echo ">> apk.static for $(uname -m)"
arch=$(uname -m)
curl -fsSL -o "$W/APKINDEX.tar.gz" "$ALPINE/$arch/APKINDEX.tar.gz"
tar -xzf "$W/APKINDEX.tar.gz" -C "$W" APKINDEX
ver=$(awk '/^P:apk-tools-static$/{p=1} p&&/^V:/{print substr($0,3); exit}' "$W/APKINDEX")
curl -fsSL -o "$W/apk-static.apk" "$ALPINE/$arch/apk-tools-static-$ver.apk"
tar -xzf "$W/apk-static.apk" -C "$W" sbin/apk.static 2>/dev/null || true
APK=$W/sbin/apk.static

echo ">> bootstrapping armv7 rootfs"
mkdir -p "$R"/etc/apk/keys
cp "$HERE"/rootfs/keys/*.pub "$R"/etc/apk/keys/
printf '%s\n' "$REPOS" > "$R"/etc/apk/repositories
# Our device files first, so package scripts see deviceinfo and the inittab.
cp -a --no-preserve=ownership "$DEV"/rootfs/. "$R"/
lists="$HERE/rootfs/packages.txt"
if has_ui xfce || has_ui lxqt || has_ui mate; then lists="$lists $HERE/rootfs/ui/x11.txt"; fi
for u in $UI; do lists="$lists $HERE/rootfs/ui/$u.txt"; done
pkgs=$(cat $lists | sed 's/#.*//' | xargs)
echo ">> desktops: $UI (boot: $SESSION)"
"$APK" --arch armv7 --root "$R" --initdb --update-cache --no-cache \
	--keys-dir "$R"/etc/apk/keys --repositories-file "$R"/etc/apk/repositories \
	add $pkgs || echo "apk reported errors; postmarketos-mkinitfs's trigger always fails here (no pmOS kernel package, xoomboot is the initramfs). Checking packages." >&2
# Package defaults may have replaced files of ours: lay the device files over again.
cp -a --no-preserve=ownership "$DEV"/rootfs/. "$R"/
for p in $pkgs; do
	"$APK" --root "$R" info -e "$p" >/dev/null || { echo "package $p missing" >&2; exit 1; }
done

echo ">> system configuration"
echo xoom > "$R"/etc/hostname
cat > "$R"/etc/hosts <<'EOF'
127.0.0.1	localhost xoom
::1		localhost xoom
EOF
cat > "$R"/etc/fstab <<'EOF'
# / is bind-mounted from /data/linux/nura by xoomboot (boot.img).
# Android userdata (incl. /sdcard = media/0) is at /mnt/userdata.
tmpfs	/tmp	tmpfs	nosuid,nodev,mode=1777,size=256m	0 0
EOF
echo 'rc_logger="YES"' >> "$R"/etc/rc.conf
mkdir -p "$R"/etc/network
cat > "$R"/etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback
EOF
# tinydm starts X from a service, not a VT: let Xorg.wrap run it, with root
# rights (there is no logind to hand out DRM/input devices).
mkdir -p "$R"/etc/X11
printf 'allowed_users=anybody\nneeds_root_rights=yes\n' > "$R"/etc/X11/Xwrapper.config
rm -f "$R"/etc/machine-id

echo ">> user account ($USER_NAME, uid $USER_UID)"
if ! grep -q "^$USER_NAME:" "$R"/etc/passwd; then
	echo "$USER_NAME:x:$USER_UID:$USER_UID:Nura user:/home/$USER_NAME:/bin/ash" >> "$R"/etc/passwd
	echo "$USER_NAME:x:$USER_UID:" >> "$R"/etc/group
	hash=$(openssl passwd -6 "$USER_PASS")
	echo "$USER_NAME:$hash:20000:0:::::" >> "$R"/etc/shadow
fi
python3 - "$R/etc/group" "$USER_NAME" <<'PY'
import sys
path, user = sys.argv[1], sys.argv[2]
want = {"wheel", "video", "audio", "input", "netdev", "plugdev", "seat",
        "feedbackd", "dialout", "tty"}
out = []
for line in open(path):
    f = line.rstrip("\n").split(":")
    if len(f) == 4 and f[0] in want:
        members = [m for m in f[3].split(",") if m]
        if user not in members:
            members.append(user)
        f[3] = ",".join(members)
    out.append(":".join(f))
open(path, "w").write("\n".join(out) + "\n")
PY
chmod 640 "$R"/etc/shadow

echo ">> firmware and drivers"
install -Dm644 "$FW/stock-wifi-nvram.txt" "$R/usr/share/nuraxoom/stock-wifi-nvram.txt"
# The Bluetooth .hcd is copied from the tablet's Android /system by the installer.
if [ -n "$XDRV" ]; then
	install -Dm755 "$XDRV" "$R/usr/lib/xorg/modules/drivers/opentegra_drv.so"
	# opentegra (GPU), back to modesetting if X fails to start twice
	sed -i 's/^modesetting$/auto/' "$R"/etc/nuraxoom/display
else
	echo modesetting > "$R"/etc/nuraxoom/display
fi

echo ">> kernel modules"
KREL=$(ls "$MODS"/lib/modules)
mkdir -p "$R"/usr/lib/modules
cp -a "$MODS/lib/modules/$KREL" "$R/usr/lib/modules/"
rm -f "$R/usr/lib/modules/$KREL/build" "$R/usr/lib/modules/$KREL/source"
depmod -b "$R/usr" "$KREL" 2>/dev/null || depmod -b "$R" "$KREL"
echo "$KREL" > "$R"/usr/share/nuraxoom/kernel.release

echo ">> home directory"
H=$R/home/$USER_NAME
mkdir -p "$H"/.local/state
cp -a "$R"/etc/skel/. "$H"/
if has_ui sxmo; then
	mkdir -p "$H"/.config/sxmo "$H"/.cache/sxmo
	# Suspend/resume is unverified on the Xoom: a failed resume looks like a dead
	# tablet. Sxmo > Config toggles this file.
	touch "$H"/.cache/sxmo/sxmo.nosuspend
	cp "$R"/usr/share/sxmo/appcfg/xinit_template "$H"/.config/sxmo/xinit
	printf '\n# NuraXoom: remember that this Xorg driver came up\n/usr/libexec/nuraxoom/x-started &\n' >> "$H"/.config/sxmo/xinit
	printf '\n# NuraXoom: follow the accelerometer (toggle: Menu > Config > Autorotate)\nsxmo_jobs.sh start autorotate sxmo_autorotate.sh &\n' >> "$H"/.config/sxmo/xinit
else
	rm -rf "$H"/.config/sxmo
fi
ln -sfn /mnt/userdata/media/0 "$H"/sdcard
chown -R $USER_UID:$USER_UID "$H"
chmod 700 "$H"

mkdir -p "$R"/var/lib/tinydm
case $SESSION in
console) boot_ui=${UI%% *} ;;
*) boot_ui=$SESSION ;;
esac
case $boot_ui in
phosh) ln -sfn /usr/share/wayland-sessions/phosh.desktop "$R"/var/lib/tinydm/default-session.desktop ;;
*) ln -sfn /usr/share/xsessions/$boot_ui.desktop "$R"/var/lib/tinydm/default-session.desktop ;;
esac
[ -e "$R$(readlink "$R"/var/lib/tinydm/default-session.desktop)" ] || { echo "no session file for $boot_ui" >&2; exit 1; }
sed -i 's/^#\? *AUTOLOGIN_UID=.*/AUTOLOGIN_UID='$USER_UID'/' "$R"/etc/conf.d/tinydm
mkdir -p "$R"/var/lib/nuraxoom "$R"/mnt/userdata
chgrp 10 "$R"/var/lib/nuraxoom; chmod 2775 "$R"/var/lib/nuraxoom   # gid 10 = wheel

echo ">> services"
rl() { mkdir -p "$R/etc/runlevels/$1"; ln -sfn "/etc/init.d/$2" "$R/etc/runlevels/$1/$2"; }
echo "$SESSION" > "$R"/etc/nuraxoom/session
rm -f "$R"/etc/runlevels/*/tinydm
[ "$SESSION" != console ] && rl default tinydm
# tinydm is the only login manager (phosh's greetd, LXQt's sddm stay off)
rm -f "$R"/etc/runlevels/*/greetd "$R"/etc/runlevels/*/sddm "$R"/etc/runlevels/*/lightdm
for s in nuraxoom-firstboot nuraxoom-wlan nuraxoom-logs nuraxoom-usb dbus bluetooth \
         networkmanager iio-sensor-proxy local udev-postmount postmarketos-zram-swap zram-init; do
	[ -e "$R/etc/init.d/$s" ] && rl default $s
done
rl boot modules
# USB networking is nuraxoom-usb (192.168.42.2 + serial console), not pmOS's
# unudhcpd. SSH stays off until the owner has changed the default password.
rm -f "$R"/etc/runlevels/*/unudhcpd.usb0 "$R"/etc/runlevels/*/sshd
# No modem on the wingray/MZ605 builds that this image targets.
rm -f "$R"/etc/runlevels/*/modemmanager "$R"/etc/runlevels/*/eg25-manager
# Plain-text syslog (/var/log/messages, mirrored to the sdcard) instead of
# logbookd's sqlite db, which has no reader in the image.
if [ -e "$R"/etc/init.d/syslog ]; then
	rm -f "$R"/etc/runlevels/*/logbookd
	echo 'SYSLOGD_OPTS="-t -s 1024 -b 2"' > "$R"/etc/conf.d/syslog
	rl boot syslog
fi
# There is no seatd: Xorg runs through Xorg.wrap as root.
rm -f "$R"/etc/runlevels/*/seatd

echo ">> privacy check"
rm -rf "$R"/etc/ssh/ssh_host_* "$R"/root/.ssh "$R"/home/*/.ssh "$R"/var/cache/apk/* "$R"/var/log/*
if grep -rIlE '^\s*psk=|^\s*wpa-psk' "$R"/etc 2>/dev/null; then
	echo "refusing: Wi-Fi credentials in the image" >&2; exit 1
fi
ls "$R"/etc/NetworkManager/system-connections/* 2>/dev/null && { echo "refusing: saved networks in the image" >&2; exit 1; }
# (Alpine's own "permit nopass keepenv root" only concerns root itself.)
if grep -rh nopass "$R"/etc/doas.d | grep -v ' cmd ' | grep -vE 'nopass( keepenv)? root$'; then
	echo "refusing: unrestricted doas nopass rule" >&2; exit 1
fi

echo ">> packing"
rm -rf "$R"/tmp/* "$R"/run/* 2>/dev/null || true
tar --numeric-owner --xattrs -C "$R" -cf - . | gzip -6 > "$OUT"
ls -l "$OUT"
