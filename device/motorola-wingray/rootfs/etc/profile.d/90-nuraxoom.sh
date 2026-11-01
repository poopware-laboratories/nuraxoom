# NuraXoom hints for interactive shells
if [ -t 1 ] && [ -z "$NURAXOOM_HINTED" ]; then
	export NURAXOOM_HINTED=1
	[ -f /etc/nuraxoom/motd ] && cat /etc/nuraxoom/motd
fi
# Created at boot by nuraxoom-firstboot (no logind in this image)
if [ -z "$XDG_RUNTIME_DIR" ] && [ -d "/run/user/$(id -u)" ]; then
	export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
