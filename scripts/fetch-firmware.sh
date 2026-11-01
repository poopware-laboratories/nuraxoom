#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Download Motorola's MZ605 stock ROM from archive.org and extract the Wi-Fi
# calibration (NVRAM) the image needs. Motorola's files are not redistributed
# in this repository: every build fetches them itself.
#   scripts/fetch-firmware.sh <workdir>
# Needs curl, unzip and debugfs (e2fsprogs). Result: <workdir>/stock-wifi-nvram.txt
set -eu
URL=https://archive.org/download/mz-600-hri-39/MZ605/H.6.1-38.4_Brazil.zip
ZIP_SHA1=f5025881ad169887a79f52942b7b91fb45abd67c
CAL_SHA256=5f21e82bb4698b44ced9f44d17c100df084781d1f01cddb7e64fcc911e9ef078
W=$1
mkdir -p "$W"
Z=$W/H.6.1-38.4_Brazil.zip
if [ ! -f "$Z" ]; then
	curl -fL --retry 3 -o "$Z.partial" "$URL"
	mv "$Z.partial" "$Z"
fi
echo "$ZIP_SHA1  $Z" | sha1sum -c -
unzip -p "$Z" system.img > "$W/system.img"
rm -f "$W/bcm4329.cal"
debugfs -R "dump /etc/wifi/bcm4329.cal $W/bcm4329.cal" "$W/system.img" 2>/dev/null
rm -f "$W/system.img"
echo "$CAL_SHA256  $W/bcm4329.cal" | sha256sum -c -
# The stock file carries one tablet's MAC; nuraxoom-wlan adds a per-tablet one.
grep -v '^macaddr=' "$W/bcm4329.cal" > "$W/stock-wifi-nvram.txt"
echo "$W/stock-wifi-nvram.txt"
