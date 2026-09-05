#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./uninstall.sh" >&2; exit 1; }

systemctl disable b580-rebar.service 2>/dev/null || true
rm -f /etc/systemd/system/b580-rebar.service
rm -f /usr/local/sbin/b580-rebar
rm -f /etc/default/b580-rebar
systemctl daemon-reload

echo "Removed the B580 ReBAR service and script."
echo "The kernel parameter pci=realloc was NOT removed automatically."
echo "Remove it using your distro/bootloader's normal method if you no longer need it, then reboot."
