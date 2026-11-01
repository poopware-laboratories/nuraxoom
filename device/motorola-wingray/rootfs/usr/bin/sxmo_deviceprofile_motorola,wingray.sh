#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Sxmo device profile: Motorola Xoom (wingray, Wi-Fi only / dead baseband)
export SXMO_NO_MODEM=1
export SXMO_TOUCHSCREEN_ID="Atmel maXTouch Touchscreen"
export SXMO_POWER_BUTTON="0:0:cpcap-pwrbutton"
export SXMO_VOLUME_BUTTON="1:1:gpio-keys"
export SXMO_MONITOR="LVDS-1"
export SXMO_MIN_BRIGHTNESS=5
# 10.1" 1280x800 panel: larger menus, landscape-first
export SXMO_DMENU_LANDSCAPE_LINES=12
export SXMO_DMENU_PORTRAIT_LINES=20
export SXMO_ROTATE_DIRECTION=right
