#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./install.sh" >&2; exit 1; }

for c in lspci setpci systemctl; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing required command: $c" >&2; exit 1; }
done

if ! lspci -D -d 8086:e20b | grep -q .; then
  echo "Intel Arc B580 (8086:e20b) not found." >&2
  exit 1
fi

if ! grep -qw pci=realloc /proc/cmdline; then
  cat >&2 <<'MSG'
ERROR: pci=realloc is not active.

Add the kernel parameter "pci=realloc", reboot, verify it with:
  cat /proc/cmdline

Then run this installer again.
See README.md for distro-specific examples.
MSG
  exit 1
fi

install -Dm0755 ./b580-rebar /usr/local/sbin/b580-rebar
install -Dm0644 ./b580-rebar.service /etc/systemd/system/b580-rebar.service

systemctl daemon-reload
systemctl enable b580-rebar.service

cat <<'MSG'
Installed and enabled b580-rebar.service.

Do NOT start it from a running graphical session: the GPU will be unbound briefly.
Reboot instead:
  systemctl reboot

After reboot verify with:
  sudo b580-rebar --check
  systemctl status b580-rebar.service --no-pager -l
MSG
