# NuraXoom

**Nura (postmarketOS-based Linux) on the Motorola Xoom.**

> This is a **community device port, not an official Nura release**. It is not
> made or supported by the Nura or postmarketOS projects; please don't send them
> bug reports about it.

NuraXoom installs a full postmarketOS-style Linux system with the
[Xfce](https://xfce.org) desktop on a Motorola Xoom, next to Android.
Nothing is formatted: Linux lives in a folder on the Android data partition, and
only the boot partition is replaced (your original one is backed up first).

## What works

| Works | Partly | Not yet |
|---|---|---|
| Touchscreen, rotation | Power button (see issues) | 5 GHz Wi-Fi |
| Wi-Fi 2.4 GHz | | OpenGL (3D apps use the CPU) |
| Bluetooth | | Cameras |
| Speakers, volume keys | | Mobile data (MZ600/MZ602/MZ605 modem) |
| Battery level and charging | | Firefox (CPU has no NEON) |
| Brightness, USB networking + serial console | | Android in the boot menu |
| Xfce, LXQt, MATE, Sxmo, Phosh desktops | | |
| GPU-accelerated X11 drawing (opentegra) | | |

Tested on an **MZ605** running the **MZ604 (wingray)** recovery. Other Xoom models
(MZ600, MZ601, MZ602, MZ604, MZ606) should work the same way but are untested.

## What you need

* A Motorola Xoom with an unlocked bootloader
* **TWRP for wingray** (tested: 2.6.3.0)
* Android still installed on the system partition: the installer copies the
  Bluetooth firmware from it (Motorola's files can't be redistributed here)
* About 2 GB free on the internal storage

## Install

1. Copy `NuraXoom-<version>-wingray-twrp.zip` and `NuraXoom-restore-boot.zip`
   to the tablet.
2. *(optional)* To connect to Wi-Fi automatically, create
   `/sdcard/NuraXoom/wifi.txt` with one network per line:
   `network name<TAB>password`. It is imported on first boot, then renamed.
3. Reboot into TWRP, choose **Install**, and pick the NuraXoom zip.
4. Reboot. The first boot takes a minute or two.

You'll be logged in automatically. The account is `user`, password `147147`
(used for `doas` and the console). **Change it:** open a terminal and run `passwd`.

### Going back to Android

Flash `NuraXoom-restore-boot.zip` in TWRP. It writes back the boot partition
saved at install time (`/sdcard/NuraXoom/backup/boot-original.img`). Linux stays in
`/data/linux/nura` until you delete it.

## Using it

* **Wi-Fi:** network icon in the panel (Sxmo: menu → Networks), or `nmtui`
* **Rotation:** follows the accelerometer. To turn it off in Xfce/LXQt/MATE:
  `mkdir -p ~/.config/nuraxoom && touch ~/.config/nuraxoom/autorotate.off`
* **On-screen keyboard:** Onboard
* **Other desktops:** images can include several (see *Building*); switch with
  `doas nuraxoom-session xfce|lxqt|mate|sxmo|phosh|console` and reboot
* **Display driver:** the Tegra 2 GPU driver (opentegra) is used by default and
  falls back to plain modesetting if X fails to start twice;
  `doas nuraxoom-display status|auto|opentegra|modesetting`
* **Packages:** `doas apk update && doas apk add <name>`
* **Logs:** `/sdcard/NuraXoom/logs` (also readable from TWRP)
* **USB:** plugged into a computer, the tablet is `192.168.42.2` on a USB network
  and also offers a serial console (`/dev/ttyACM0` on Linux, `/dev/cu.usbmodem*`
  on macOS). For SSH: `doas apk add openssh && doas rc-update add sshd && doas rc-service sshd start`

## Known issues

* A power-management interrupt (IRQ 53) is disabled by the kernel about 50 s
  after boot. The power button has kept working anyway; we're investigating.
* Rotation occasionally doesn't start at boot; `doas rc-service iio-sensor-proxy restart` fixes it.
* The clock is in UTC until you pick a time zone: `doas setup-timezone`.
* Suspend is disabled (resume is untested).

## Building it yourself

On Linux (or a Linux VM) with an ARM cross compiler, `qemu-arm` binfmt support,
`e2fsprogs`, `curl`, `unzip` and `python3`:

```sh
# 1. kernel: xoom-linux at the pinned commit + kernel/patches
git clone https://github.com/xoom-linux/linux && git -C linux checkout 2404d27378503b4df74ab2cb0a8b7cd6cf9d5fc3
scripts/build-kernel.sh linux out/kernel
# 2. Motorola Wi-Fi calibration, downloaded from an archived stock ROM
scripts/fetch-firmware.sh out/firmware
# 3. root filesystem, bootstrapped from the Nura and Alpine repositories (as root)
#    NURAXOOM_UI picks the desktops: xfce (default), lxqt, mate, sxmo, phosh,
#    several ("xfce,sxmo") or all; the first one starts on boot
#    (NURAXOOM_SESSION overrides, "console" = text console)
sudo NURAXOOM_UI=xfce rootfs/build-nura-rootfs.sh out/kernel/modules out/firmware \
    out/nura-rootfs.tar.gz packages/xf86-video-opentegra/prebuilt/opentegra_drv.so
# 4. boot image (xoomboot) and the TWRP zips
#    (busybox.static: /bin/busybox.static from the rootfs)
boot/build-boot.sh out/kernel/zImage out/kernel/tegra20-motorola-mz605.dtb busybox.static 0.4.0 out/boot.img
installer/build-zips.sh 0.4.0 out/boot.img out/nura-rootfs.tar.gz busybox.static out/
```

Layout:

* `boot/` – **xoomboot**, the small BusyBox initramfs that boots
  `/data/linux/<name>`
* `kernel/` – kernel source pin, patches, config
* `device/motorola-wingray/` – device files (services, Xorg config, Sxmo device
  profile)
* `rootfs/` – package list and rootfs builder
* `installer/` – TWRP install / restore zips
* `HANDOFF.md` – detailed development notes

## License

Our scripts, xoomboot and device files: GPL-2.0-or-later (see `LICENSE`). Kernel
patches and device tree: GPL-2.0, like the kernel. `tools/mkbootimg.py` is MIT.
The bundled `opentegra_drv.so` is built from
[xf86-video-opentegra](https://github.com/grate-driver/xf86-video-opentegra) (MIT)
with `packages/xf86-video-opentegra/build.sh` (native Alpine armv7 build).
Motorola firmware is not included; it's fetched at build or install time.

## Thanks

[xoom-linux](https://github.com/xoom-linux) for the mainline kernel and device
tree, the [grate](https://github.com/grate-driver) project for the Tegra 2
graphics work, and [postmarketOS](https://postmarketos.org), Nura,
[Alpine](https://alpinelinux.org) and [Sxmo](https://sxmo.org).
