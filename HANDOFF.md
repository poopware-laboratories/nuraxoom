# NuraXoom port – handoff notes (2026-10-31)

Fresh port of **Nura** (postmarketOS/Alpine-based) to the **Motorola Xoom, wingray
target** (owner's MZ605 has a dead baseband). Everything ChatGPT built in the parent
`NuraXoom/` folder is *superseded*; only its upstream sources and package payloads
are used as inputs. This `port/` folder is the new project and becomes the GitHub
repo **after** the TWRP zip is tested on the tablet. Nura does not accept AI
contributions: nothing is submitted upstream; README must say "community device
port, not an official Nura release".

## Design

* `boot/init` – **xoomboot**: tiny BusyBox initramfs in the 8 MiB `boot` partition.
  Mounts userdata, lists every OS in `/data/linux/<name>/` (any distro: Nura,
  Gentoo, Debian…), volume-key menu (Vol- next, Vol+/Power boot), per-OS
  `/data/linux/<name>.conf` (INIT=…), global `/data/linux/boot.conf`
  (DEFAULT=, TIMEOUT=), shared modules in `/data/linux/.kernel/modules`.
  Logs + pstore to `/sdcard/NuraXoom/logs` (readable from TWRP; USB cable is dead).
  Userdata is moved to `/mnt/userdata` inside the booted OS.
* `kernel/` – xoom-linux/linux @ 2404d273 (linux-next 7.0 + Wingray DTS), pinned in
  `kernel/SOURCE`; `tegra_defconfig` + `xoom.config`; patch: brcmfmac must not fail
  probe when the OOB IRQ can't be a wake source (old Wi-Fi failure, -6/-ENXIO).
  DTB: `tegra20-motorola-wingray.dtb` appended to zImage. Build: `scripts/build-kernel.sh`.
* `rootfs/build-nura-rootfs.sh` – takes a Nura armv7 base tarball, strips old
  ChatGPT leftovers + credentials, adds user `user` (uid 10000, pw 147147, wheel),
  tinydm autologin into **Sxmo (dwm, X11)**, modules, firmware, device package.
* `device/motorola-wingray/` – Sxmo device profile, Xorg configs, display-driver
  auto-fallback (opentegra → modesetting after 2 failed X starts; `nuraxoom-display`),
  Wi-Fi without NetworkManager (`nuraxoom-wlan` service, `nuraxoom-wifi-menu` touch
  menu, `/sdcard/NuraXoom/wifi.txt` import), stable MAC from eMMC CID, log mirroring
  service, BCM4329 NVRAM/HCD from stock MZ605 firmware (see firmware/SOURCE.json).
* `packages/xf86-video-opentegra/` – Tegra 2 GR2D/EXA X driver rebuilt from
  github.com/grate-driver/xf86-video-opentegra @ 9be4b4a with zig cc
  (arm-linux-musleabihf, cortex-a9, no NEON) against Ubuntu's Xorg 21.1 SDK headers
  with `_XSERVER64` removed; all 214 undefined symbols verified against Nura's
  Xorg 21.1.25 + libs. NEEDED fixed to libc.musl-armv7.so.1 with patchelf.
  Prebuilt `.so` is in `prebuilt/`.
* `installer/` – TWRP zip: verifies sha256 of payload, backs up boot to
  `/sdcard/NuraXoom/backup/boot-original.img` (+ timestamped copy), extracts rootfs
  to `/data/linux/nura` (upgrade keeps /home, Wi-Fi, ssh keys), writes boot.img,
  verifies readback. Never formats, never touches system/recovery.
  `NuraXoom-restore-boot.zip` writes the original boot back.

## Package base

No Alpine/Nura mirror was reachable from the build workspace, so the rootfs base is
the most intact package set already on disk:
`../dist/profiles/sxmo-video-private-v3/nura-rootfs.tar.gz` (622 packages, files match
the apk database except vim-common runtime → `doas apk fix vim-common` once online).
It contains the owner's Wi-Fi credentials and SSH key; the build script deletes them
and refuses to build if a psk= line survives. CI (GitHub Actions has full network)
should instead bootstrap with apk.static from mirror.nura.eco + Alpine edge.

## Status when this note was written

- [x] kernel config + patch, xoomboot init, device package, installer scripts
- [x] opentegra driver built and symbol-checked
- [x] kernel build finished (Lima VM `nuraxoom`, Ubuntu LTS arm64, gcc 15.2
      cross; 2026-10-31). gzip zImage was 8.7 MB > 8 MiB boot partition →
      `CONFIG_KERNEL_XZ=y`; zImage+DTB now 6.0 MB, boot.img 6.65 MB.
- [x] rootfs assembled, boot.img + zips built (`out/`), credential leak scan clean.
      Fixed on the way: repo files were mode 600, so `cp -a` would have put
      non-executable, non-root-owned scripts in the rootfs.
- [x] 0.1.1 (same day, tablet out of battery, untested):
      * installer: device check reads prop files + accepts "Hardware: Stingray"
        (MZ604 TWRP aborted with device ''); boot/userdata lookup falls back to
        the recovery fstab, restore zip too.
      * kernel patch 0002: cpcap-adc programs ADCC1/ADCC2 idle defaults before
        the first conversion (likely cause of upstream's ADC -ETIMEDOUT; Motorola
        wrote ADCC1=0x9000 ADCC2=0x4136 at PMIC init). cpcap_adc is now =m and
        blacklisted (upstream: power button IRQ dies while ADC loaded). Test on
        device: Sxmo Scripts > "Battery ADC test" (nuraxoom-adc-test) → logs/adc-test.txt;
        then check the power button. If both work: drop the blacklist and try
        enabling the cpcap-battery DT node (note: 2S pack, 8.4 V max).
      * rootfs: base has seatd-openrc but no seatd binary (dropped from runlevel);
        added Xwrapper.config (allowed_users=anybody, needs_root_rights=yes) since
        tinydm starts X without a VT; /etc/network/interfaces with lo;
        wpa_supplicant.conf 0600; power.txt (lsmod + power_supply) in logs.
- [x] 0.1.2 (X/session audit; armv7 binaries smoke-tested with `qemu-arm -L <rootfs>`
      in the Lima VM — no binfmt for arm on Apple Silicon hosts):
      * opentegra_drv.so could NOT load: musl binds all symbols at dlopen, and
        exaGetPixmapDriverPrivate lives in libexa, which the driver only loads in
        PreInit. Fixed with `Load "exa"` in nuraxoom-opentegra.conf; emulated Xorg
        now loads it (ABI 25.2) and only fails at TegraOpenHardware (no GPU in VM).
      * no logind/pam_rundir: nuraxoom-firstboot creates /run/user/<uid>,
        profile.d exports XDG_RUNTIME_DIR; xoomboot /run tmpfs 8m -> 10%.
      * logbookd (sqlite, no reader) -> busybox syslogd /var/log/messages; rc.log
        mirrored; ntpd enabled; CONFIG_PANIC_TIMEOUT=10 so pstore gets saved.
      * ~/.cache/sxmo/sxmo.nosuspend shipped (Tegra20 resume unverified).
      * Checked OK: PAM stack (/usr/lib/pam.d, only optional modules missing),
        autologin VT handling, startx/xinit, brcmfmac .zst firmware + FW_LOADER_COMPRESS_ZSTD,
        udhcpc default.script, panel path RGB→lvds-encoder→panel-lvds (LVDS-1),
        LP8550/mXT/LM90 drivers, pstore (PSTORE_RAM=y).
- [x] 0.1.3: free-space check read the wrapped busybox df line as 0 MiB on the tablet
      (device check + partition lookup passed); now `df -Pk`, last line, $(NF-2).
- [x] 0.1.3 flashed (2026-11-01): black screen, reboots by itself ~30 s in, every
      boot; /sdcard/NuraXoom/logs stays empty, so the reset is before xoomboot
      mounts /data (kernel init). Diff against the last image that booted on this
      tablet (ChatGPT sxmo-video-private-v3, same xoom-linux tree, mz605 DTB =
      renamed wingray DTS): it had no cpufreq, cpuidle, TEGRA20_EMC, Tegra
      watchdog. Also the old ramoops at 0x1ff00000 is the stock ram_console, which
      the TWRP kernel wipes.
- [x] 0.1.4: those four off in xoom.config; patch 0003 moves ramoops to 0x1fe00000
      (stock kernel memblock_remove()s it but never uses it); xoomboot saves logs +
      pstore right after mounting /data; `NuraXoom-save-crashlog.zip` dumps that MiB
      from /dev/mem in TWRP (+ strings of the console zone), decode with
      `scripts/decode-ramoops.py`. Re-enable the PM features one at a time once it boots.
- [x] 0.1.4 on the tablet: same loop. save-crashlog: TWRP kernel refuses /dev/mem.
      Owner: screen flashes (display takeover) 30-60 s in, then backlight on +
      black until the reboot. ChatGPT's working images booted from /system and found
      it by UUID with a 30 s wait; xoomboot gave userdata only 10 s, then die() wrote
      its message once (before the panel was up) and rebooted 60 s later, unable to
      save logs. 0.1.5 (boot-only zip, rootfs unchanged): 90 s wait with progress,
      die() redraws message + /sys/class/block + mmc/error dmesg every 5 s for 2 min.
      `NuraXoom-test-oldkernel.zip`: ChatGPT's kernel+DTB with xoomboot 0.1.5.
      `installer/build-bootonly-zip.sh` makes these; kernel built from ChatGPT's
      config is in the VM at ~/out/kernel-oc (LOCALVERSION -nuraxoom-oc).
- [x] 0.1.5 on the tablet: no early reboot any more; splash, white flicker at the
      bottom, then backlit black for minutes, then reboot (~= 90 s wait + 2 min die
      screen). The die text never became visible either, so with my kernel nothing
      reaches the screen at all.
- [x] 0.2.0 = reset to known-good, change one thing per build from here:
      ChatGPT's sxmo-video-v3 zImage + tegra20-motorola-mz605.dtb + its modules
      (from the base tarball, 7.0.0-next-20260422-mz605-nura-v1+), unchanged;
      ChatGPT's cmdline `console=tty0 loglevel=6 printk.time=1 rdinit=/init cma=64M`;
      session=console (NURAXOOM_SESSION=console): tty1 runs console-session
      (fbkeyboard + login -f user), tinydm off; `doas nuraxoom-session sxmo` turns
      the desktop on. My kernel work (xoom.config, patches 0001-0003) is parked
      until the console boots. The owner's original "Wi-Fi works" console image is
      not on this Mac any more.
- [x] 0.2.0 BOOTS on the tablet (2026-11-01): kernel text, xoomboot (paused a while,
      likely the userdata wait), Nura console. Touch does nothing.
- [x] 0.2.1 (`NuraXoom-0.2.1-update.zip`, overlay zip from installer/build-overlay-zip.sh,
      only replaces files in /data/linux/nura): fbkeyboard started with setsid -
      console-session started it in the tty's session and then exec'd login, whose
      vhangup() SIGHUPs it (ChatGPT started it from inside the logged-in shell).
      logs-loop writes input.txt (/proc/bus/input/devices, /dev/input, ps, fbkeyboard.log).
- [x] 0.2.1: touch works in the console. `nuraxoom-session sxmo` + modesetting:
      Sxmo comes up (2026-11-01).
- [x] 0.2.2 update: Sxmo picks its profile from the first DT compatible, which is
      motorola,mz605 with ChatGPT's DTB, so the Xoom profile was never loaded;
      added sxmo_deviceprofile_motorola,mz605.sh -> wingray profile.
- [x] 0.2.3 update: no wlan0 - brcmfmac/btbcm look for board files named after the
      first DT compatible (motorola,mz605 with ChatGPT's DTB); only the wingray
      names were installed. Added mz605 -> wingray symlinks for the NVRAM .txt and
      the BT .hcd. (Firmware .bin.zst is fine: FW_LOADER_COMPRESS_ZSTD=y.)
- [x] Owner tests on 0.2.0+0.2.1: brightness works; power button: cpcap-pwrbutton is
      registered but evtest shows no events (CPCAP_ADC=y in ChatGPT's kernel - the
      known upstream IRQ conflict); sound card registers, speakers silent (mixer).
- [x] 0.2.4 PRIVATE update (out/ only, gitignored): 0.2.3 + diag.txt in logs + owner's
      home Wi-Fi in wpa_supplicant.conf + temporary dev SSH (key-only, AllowUsers
      user, key ~/.ssh/nuraxoom_xoom_ed25519 on the build Mac, overlay in
      out/ssh-overlay via EXTRA_ROOT). DELETE out/ssh-overlay, the PRIVATE zip and
      the network from the tablet before anything ships; full-zip builds never
      include them (leak scan refuses psk=).
- [x] 0.2.5 (+ PRIVATE): wlan0 still missing with 0.2.3 names. ChatGPT's working
      xoom-wifi appended macaddr=02:... to the (MAC-stripped) stock NVRAM before
      modprobe brcmfmac; mine only set the MAC with ip link after wlan0 existed.
      nuraxoom-wlan now writes brcmfmac4329-sdio.motorola,{wingray,mz605}.txt =
      /usr/share/nuraxoom/stock-wifi-nvram.txt + macaddr (from eMMC CID), then
      rmmod/modprobe brcmfmac. Unverified: if still no wlan0, need dmesg | grep brcm.
- [x] 0.2.5 on the tablet: wlan0 appears (macaddr fix works); 5 GHz does not
      associate (known from earlier Linux attempts), 2.4 GHz "02-2G" works via
      nuraxoom-wifi-menu, IP <tablet LAN IP>. SSH: host key OK, publickey refused -
      TWRP's busybox tar created /etc/ssh/nuraxoom-authorized_keys with its own
      umask (no dir entries in the overlay); sshd StrictModes. Owner to chmod 755/644.
      Volume keys work (gpio-keys); BT service starts (controller unverified).
      Firefox segfaults: ARM Firefox/Chromium need NEON, Tegra 2 has none.
- [x] 0.3.0 full zip (2026-11-01): everything folded in; defaults session=sxmo,
      display=modesetting; NURAXOOM_PACKAGES="netsurf dillo" (rootfs build installs
      packages in a chroot - needs an armv7 binfmt: on the Lima VM register
      /usr/bin/qemu-arm (static-pie) with flags FP, Ubuntu skips it on arm64);
      overlay zips now carry directory entries (modes) for EXTRA_ROOT.
      0.3.0 PRIVATE update = home Wi-Fi (2G priority) + dev SSH. Host alias:
      ssh -F ~/.ssh/nuraxoom_config xoom (separate known_hosts).
- [x] power-button test kernel: ChatGPT kernel rebuilt in ~/src/linux-gpt (worktree,
      its 3 patches + mz605 dts + its shipped config; DTB byte-identical to the
      shipped one) with only CPCAP_ADC=m, release 7.0.0-next-20260422-mz605-nura-v1-pb
      (~/out/kernel-pb). NuraXoom-0.3.0-test-powerbutton.zip = its boot image +
      modules (EXTRA_ROOT) + modprobe.d blacklist. Undo: 0.3.0 PRIVATE update.
- [x] Owner flashed 0.3.0 full + PRIVATE (2026-11-01). USB cable works: TWRP adb is
      available (serial 0123456789ABCDEF); production Xoom has no `fastboot boot`.
      sshd log confirmed the earlier refusal (StrictModes, key dir modes) - fixed.
      Last-boot diag: tegra drm/host1x/vde up, X = modesetting, glamor refused
      (llvmpipe only, no Tegra Mesa) -> no acceleration; CPCAP card registered,
      codec reports "HP plugged in" at boot (speaker silence lead); BT BCM4329B1
      patch loads, then 0xfc45 tx timeout / reset -110; brcmfmac: no clm_blob
      (limited channels - 5 GHz lead); kxtf9 + ak8975 present (rotation);
      power_supply empty.
- [x] 0.3.1 update (+PRIVATE): USB gadget service nuraxoom-usb (configfs ECM
      192.168.42.2, udhcpd gives the computer .1 with no router; ACM serial with
      getty via usb-getty), inittab now lives in the device package, diag uses
      amixer -c 0 (default ALSA device goes to pipewire: "Host is down").
- [x] 0.3.1 PRIVATE installed over adb (TWRP busybox unzip has no -d: use unzip -p);
      SSH works over Wi-Fi AND USB (Mac gets 192.168.42.1 from the tablet's udhcpd).
      Dev-only doas rule `permit nopass user as root` (/etc/doas.d/99-nuraxoom-dev.conf,
      also in out/ssh-overlay - remove at ship).
- [x] Live diagnosis 2026-11-01 (ssh -F ~/.ssh/nuraxoom_config xoom):
      * zram failed: zramstart defaults to zstd, kernel has lzo/lzo-rle ->
        deviceinfo_zram_swap_algo="lzo-rle" (1.5 GB swap now).
      * AUDIO root cause: PCM RUNNING but hw_ptr stuck at 32; CPCAP VAUDIOC=0x0000
        while regulator core says vaudio enabled (summary 0 mV). Bit 0 of VAUDIOC is
        the vaudio voltage selector (0 V / 2.775 V) and cpcap_default_regs[] in
        sound/soc/codecs/cpcap.c clears mask 0x3F at codec init -> rail off behind the
        core -> no codec clock. Patch 0004 (mask 0x28). Routing for the speakers:
        "Lineout Left/Right" = HiFi, HiFi volume ~12 (DT: Int Spk <- LINEL/LINER).
        cdev1 = 26 MHz osc (correct), CPCAP is I2S provider (CBP_CFP, ChatGPT 0002).
      * Rotation: kxtf9 works (z +488 raw flat); iio-sensor-proxy claim denied (no
        logind -> no active session) -> /etc/polkit-1/rules.d/50-nuraxoom.rules
        (claim-sensor for group input); monitor-sensor works. Tablet flat reports
        "face-down": z sign of the mount matrix likely wrong (cosmetic).
      * Bluetooth: DT max-speed 3375000 > 3 Mbaud -> hci_bcm sends 0xfc45 (48 MHz
        UART clock), BCM4329B1 never answers -> capped at 3000000 in
        kernel/gpt/tegra20-motorola-mz605.dts (ChatGPT's DTS, now kept here).
- [x] NuraXoom-0.3.2-test-kernel.zip: ChatGPT kernel (~/src/linux-gpt) + CPCAP_ADC=m +
      0004 audio fix + BT 3 Mbaud DTB, release ...-mz605-nura-v1-pb, modules included;
      also zram/polkit fixes. Undo: 0.3.1 PRIVATE update (has the 0.3.0 boot image).
- [x] 0.3.2 test kernel installed over SSH (boot = /dev/mmcblk0p7, backup
      boot-before-20261101-195636.img; modules in /usr/lib/modules/...-v1-pb). Results:
      * POWER BUTTON WORKS (evtest KEY_POWER; Sxmo unlock/screenoff/lock cycle).
        Confirms the CPCAP ADC (built in) kills the pwrbutton IRQ; ADC stays =m.
      * SPEAKERS WORK (owner heard Front_Center; hw_ptr runs, VAUDIOC=0x0005).
        Boot route: /etc/local.d/nuraxoom-audio.start (Lineout L/R = HiFi, HiFi 12).
      * ROTATION WORKS: polkit rule + Sxmo autorotate job; touch matrix follows.
        Autostarted from ~/.config/sxmo/xinit (build script appends it). Testing
        sxmo scripts over ssh needs the session env (SXMO_WM etc. from dwm's environ).
      * Bluetooth: still fails, now at the first HCI Reset (0x0c03) at 115200 -
        not caused by the max-speed change (only used after setup). Suspect: the
        shared reg_wifi_vdd (ChatGPT 0001) power-cycled by nuraxoom-wlan's
        rmmod/modprobe brcmfmac. Parked.
- [x] Sxmo Wi-Fi icon: ~/.config/sxmo/hooks/sxmo_hook_statusbar.sh (skel) answers
      wifi from wpa_cli (level from scan_results: brcmfmac 4.220 gives RSSI -9999
      via signal_poll, no /proc/net/wireless), passes the rest to the default hook.
      Live on the tablet; new homes get it from /etc/skel (upgrades keep /home).
- [x] GPU (2026-11-01): driver selection never worked before - Alpine's setuid
      Xorg.wrap starts Xorg with an EMPTY environment, so XORGCONFIG was dropped and
      X always autoconfigured modesetting. Fix: ~/.xserverrc (skel) passes
      -config "$XORGCONFIG". Then nuraxoom-modesetting.conf turned out broken
      (ShadowFB / AccelMethod none -> ScreenInit failed): now minimal. Switching
      drivers needs a reboot: `rc-service tinydm restart` leaves the old Xorg
      running (drmSetMaster busy), killing X leaves DRM unusable until reboot.
      opentegra WORKS on Tegra20 (EXA HW accel, first try) but was very slow:
      runtime PM powered GR2D up/down per job (80-95 % sys CPU idle) -> keep
      gr2d+host1x power/control=on (local.d/nuraxoom-gpu.start, opentegra only);
      AccelCompositing false (text/alpha in pixman). Owner: "slower than
      modesetting, way more usable than before" -> default stays modesetting,
      opentegra selectable (Scripts > Display driver).
      Sxmo hooks need "# configversion: <hash of the default hook>" or Sxmo
      disables them (.needs-migration).
- [x] BLUETOOTH WORKS (2026-11-01, live; scan finds devices). Three causes:
      1. DT max-speed 3375000 > 3 Mbaud -> 0xfc45 (48 MHz clock) unsupported;
         3000000 is no exact Tegra UART divisor -> link dead after early switch.
         Now 921600 (kernel/gpt/tegra20-motorola-mz605.dts).
      2. hci_bcm switched baud before patchram ("early set baudrate"): after the
         patch the chip stopped answering. kernel/gpt/0005: match data for
         motorola,stingray-bcm4329-bt (no_early_set_baudrate, no_uart_clock_set),
         as Android brcm_patchram_plus (patch at 115200, then switch).
      3. The MZ605-Brazil bcm4329.hcd (ChatGPT's archive.org source) kills the
         chip after patching. The wingray hcd from Jelly Bean /system
         (/etc/firmware/bcm4329.hcd, sha256 fe8c49c4...) works ("Generic FMRX
         38.4 MHz"). firmware/BCM4329B1.motorola,wingray.hcd replaced. Fetch
         script must take the hcd from a wingray image.
      Live tablet: boot-0.3.3-test (921600 DTB) + patched hci_uart.ko (-pb).
      TODO: per-tablet BD address (controller reports 43:29:B0:00:72:84).
- [x] Wi-Fi icon still X: no sxmobar binary in the image - sxmo_common.sh defines a
      sxmobar() fallback; the hook must `. sxmo_common.sh`. Fixed.
- [x] BATTERY WORKS (2026-11-01, live; UPower + Sxmo see it). Not the CPCAP: the
      pack has a DS2781 gauge (answers with family 0x32) on the Tegra20 one-wire
      controller, as in Motorola's kernel. Pieces (kernel/gpt/):
      * tegra_w1.c: port of the Tegra OWR master (0x7000c600, SPI 30, clk/rst 71,
        1 MHz, Motorola timings in the OF match data); Kconfig W1_MASTER_TEGRA.
      * DTS owr@7000c600 node (boot-0.3.4-test).
      * 0006: w1_ds2781 also registers family 0x32 (+ module alias).
      * 0007: power-supply name "battery" - dev_name() is longer than the
        20-char thermal zone limit, probe failed with -EINVAL.
      * config: W1=m W1_MASTER_TEGRA=m W1_SLAVE_DS2781=m BATTERY_DS2781=m.
      Reads: 47 %, 7.9 V, +1.28 A charging, 37.7 C. Aliases (of:, w1-family-0x32,
      platform:) are all present, so autoload at boot should work - verify on the
      next reboot. Gotcha: `modprobe w1_ds2781` while a 0x32 slave is already bound
      to the default family deadlocks (w1_reconnect_slaves -> request_module of the
      module still loading); kill the nested modprobe. Boot order doesn't hit it.
      UPower energy-full == energy (no charge_full), cosmetic.
- [ ] Rotation broke this boot: iio-sensor-proxy reported HasAccelerometer=false,
      so sxmo_autorotate.sh exits at start. `rc-service iio-sensor-proxy restart`
      + restarting the autorotate job fixed it. udev-settle already runs in sysinit,
      so it is not that; capture G_MESSAGES_DEBUG=all proxy output on next boot.
      Reboot 2026-11-01 18:05: proxy found the accel and autorotate ran, so the
      race is intermittent.
- [x] Other DEs (2026-11-01, modesetting): MATE (mate-desktop-environment +
      onboard, ~500 MB) runs and the owner says it is "really smooth" - best
      non-Sxmo candidate. Window Maker also starts. Switch sessions with
      tinydm-set-session + a clean `rc-service tinydm stop/start`; pkill'ing Xorg
      repeatedly leaves ScreenInit failing until reboot.
- [x] Battery autoload verified after reboot (tegra_w1, w1_ds2781, ds2781_battery
      load on their own; 51 %, charging).
- [ ] CPCAP IRQ 53 (LIC 86) "nobody cared" at ~50 s on EVERY boot: ~100k irqs in
      50 s (~2000/s from probe on), while INT1-4 show no unmasked pending bits.
      The line looks asserted while idle. Lead: polarity. The CPCAP node is
      GIC_SPI 86 LEVEL_HIGH (the PMU interrupt through the PMC), and wingray's pmc
      node sets nvidia,invert-interrupt (PMC_CNTRL bit 17). Check Motorola's
      stingray board code for PMC_CNTRL INTR_POLARITY; try a DTB with
      `/delete-property/ nvidia,invert-interrupt;` in the mz605 pmc node and see if
      the count stays low. The power button counted presses on the previous boot
      even after the IRQ was disabled; not tested after this reboot.
- [ ] Clock is right but there is no /etc/localtime (UTC). Owner tablet set to
      America/Sao_Paulo by hand; image/README should say `doas setup-timezone`.
- [ ] next:
      BT power sequencing,
      then fold all into 0.4.0 full zip
- [ ] TODO (owner request, later): Android in the xoomboot menu. Plan: boot-partition
      swap - menu entry writes /sdcard/NuraXoom/backup/boot-original.img to boot,
      verifies, reboots; a root script on Android writes xoomboot back. kexec into
      the stock 2.6.39/3.x ATAG kernel (kexec-hardboot, as MultiROM on Tegra 3) is a
      possible later experiment, not a promise.
- [ ] next: SSH in, test everything; then kernel = ChatGPT config + patches with
      CPCAP_ADC=m (power button), audio mixer, opentegra, battery
- [ ] then one step at a time: sxmo with modesetting, opentegra, then my kernel
- [ ] then: GitHub repo + CI, battery (CPCAP ADC, cpcap-battery node is disabled in
      DTS), audio routing, rotation, libvdpau-tegra; cameras (OV5650/SOC2030, no
      mainline sensor drivers) last

## Rebuild steps

```sh
# kernel (needs gcc-arm-linux-gnueabihf)
git clone https://github.com/xoom-linux/linux && git -C linux checkout 2404d27378503b4df74ab2cb0a8b7cd6cf9d5fc3
scripts/build-kernel.sh linux out/kernel
# rootfs (as root)
rootfs/build-nura-rootfs.sh BASE.tar.gz out/kernel/modules out/nura-rootfs.tar.gz \
    packages/xf86-video-opentegra/prebuilt/opentegra_drv.so
# boot image + zips (busybox.static from the Nura base: usr/bin/busybox.static)
boot/build-boot.sh out/kernel/zImage out/kernel/tegra20-motorola-wingray.dtb busybox.static 0.1.0 out/boot.img
installer/build-zips.sh 0.1.0 out/boot.img out/nura-rootfs.tar.gz busybox.static out/
```

## 0.4.0 public release - in progress (2026-11-01)
Owner decisions: GitHub repo vgs499p/nuraxoom, public, contents = port/ only,
license GPL-2.0-or-later (kernel patches/DTS GPL-2.0).
Done:
- kernel/: old recipe replaced. kernel/patches/0001-0009 = ChatGPT 0001-0003 +
  cpcap vaudio + hci_bcm no-early-baud (regenerated on top of 0001) + w1_ds2781
  0x32 + ds2781 name + tegra_w1 master + mz605 DTS. Verified: applying them to
  clean 2404d273 reproduces ~/src/linux-gpt byte for byte. Full config in
  kernel/config-motorola-mz605.armv7 (LOCALVERSION -nuraxoom).
  scripts/build-kernel.sh rewritten; clean build running in VM -> ~/out/kernel-040
  (log ~/out/kernel-040.log).
- Wi-Fi cal test: wingray /system bcm4329.cal is WORSE on MZ605 (owner noticed);
  owner tablet restored to the MZ605 cal (4f387ecb...). Unloading brcmfmac live
  (needs `modprobe -r brcmfmac_wcc brcmfmac`) crashed/rebooted the tablet.
Left:
1. Blobs out of git: delete device/.../firmware/*.hcd,*.txt and
   usr/share/nuraxoom/stock-wifi-nvram.txt; build-time fetch from archive.org
   (reuse ../scripts/prepare-stock-firmware.py logic: MZ605 Brazil zip, debugfs
   dump /etc/wifi/bcm4329.cal, strip macaddr). BT hcd: installer copies
   /system/etc/firmware/bcm4329.hcd (wingray hcd works, MZ605 hcd kills BT).
2. Fresh rootfs bootstrap with apk.static (mirror.nura.eco/postmarketos/master +
   Alpine edge) incl. postmarketos-ui-sxmo-de-dwm(-openrc) = real pmOS Sxmo config
   (brings NetworkManager, base-ui themes). Then: nuraxoom-wlan only prepares
   NVRAM + loads module when NM exists; import-wifi -> NM keyfiles; NM
   unmanaged usb0; drop custom statusbar hook, Wi-Fi + ADC userscripts.
3. No private overlay (no Wi-Fi creds, SSH key, doas nopass); leak scan.
4. README (community port, not an official Nura release), LICENSE, git init in
   port/, push to vgs499p/nuraxoom, build 0.4.0 zip locally.
Update (later 2026-11-01): items 1-4 done. 0.4.0 built: fresh rootfs from
mirror.nura.eco + Alpine edge main/community/testing (testing: routewrangler,
needed by postmarketos-base-ui-networkmanager), postmarketos-ui-sxmo-de-dwm,
NetworkManager instead of our wpa_supplicant/udhcpc, sshd and pmOS unudhcpd off,
kernel 7.0.0-next-20260422-nuraxoom from the clean patch series. Blobs: Wi-Fi
NVRAM from scripts/fetch-firmware.sh (archive.org, sha-checked), BT .hcd copied
by the installer from /system. Not yet booted on hardware.

## Wayland desktops (2026-11-01, on 0.4.0)
- Alpine armv7 Mesa (libgallium 26.2.6) is built with NEON (readelf:
  Tag_Advanced_SIMD_arch NEONv1). The Tegra 2 has none: glxgears and anything
  else drawing through llvmpipe dies with SIGILL. Same root cause as Firefox.
- Catacomb: SIGILL (smithay GLES, no software path) - cannot run.
- Phosh: WORKS (slow) with WLR_RENDERER=pixman + GSK_RENDERER=cairo + seatd
  (etc/tinydm.d/env-wayland.d/90-nuraxoom-nogl). postmarketos-ui-phosh enables
  greetd: remove it from the default runlevel when tinydm is the DM.
- Plasma Mobile/Desktop (KWin, no QPainter in Plasma 6) and Lomiri (Mir +
  Qt Quick) need GL: expected to hit the same SIGILL. Not installed/tested.
- Real fix for all GL users: a non-NEON Mesa build (or the GR3D driver).
- apk "1 error" fixed: deviceinfo moved to /etc/deviceinfo, so the
  postmarketos-mkinitfs trigger skips itself (it found no kernel package).
- Phosh tuning (owner's tablet, Phosh now the default session there):
  * The heavy load under Phosh was Sxmo's session left running after tinydm
    stopped: autologin puts the session in its own cgroup, so
    rc_cgroup_cleanup misses it; superd kept a 2nd PipeWire/WirePlumber
    spinning (~64 % CPU). etc/conf.d/tinydm now records the session cgroup in
    stop_pre and writes cgroup.kill in stop_post. CPU ~95 % idle afterwards.
  * Animations off (gsettings org.gnome.desktop.interface enable-animations).
  * etc/skel/.config/autostart hides gsd print/sharing/wwan/smartcard/usb/
    color, Evolution alarms, mmsd, vvmd, geoclue demo: 607 MB available vs
    <100 MB free before.
  * Never restart pipewire-pulse under a running Phosh: its volume control
    asserts in libpulse and takes the whole session down.
  * CPU runs at 1 GHz always (no cpufreq for this board); custom Android
    kernels ran 1.4-1.5 GHz with raised voltage - possible opt-in later.
