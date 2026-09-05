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

AUTO_ADDED_KARG=0

if ! grep -qw pci=realloc /proc/cmdline; then
  if command -v rpm-ostree >/dev/null 2>&1; then
    echo 'pci=realloc is not active. Detected an rpm-ostree system; adding it automatically...'
    rpm-ostree kargs --append-if-missing="pci=realloc"
    AUTO_ADDED_KARG=1
  else
    cat >&2 <<'MSG'
ERROR: pci=realloc is not active and this installer could not add it automatically.

Add the kernel parameter "pci=realloc" using your distribution/bootloader, reboot,
verify it with:
  cat /proc/cmdline

Then run this installer again. See README.md for Fedora/RHEL and Debian/Ubuntu examples.
MSG
    exit 1
  fi
fi

install -Dm0755 ./b580-rebar /usr/local/sbin/b580-rebar
install -Dm0644 ./b580-rebar.service /etc/systemd/system/b580-rebar.service

systemctl daemon-reload
systemctl enable b580-rebar.service

if [[ $AUTO_ADDED_KARG -eq 1 ]]; then
  echo
  echo 'Added pci=realloc to the rpm-ostree kernel arguments.'
fi

cat <<'MSG'
Installed and enabled b580-rebar.service.

Do NOT start it from a running graphical session: the GPU will be unbound briefly.
Reboot once to activate everything:
  systemctl reboot

After reboot verify with:
  sudo b580-rebar --check
  systemctl status b580-rebar.service --no-pager -l
MSG
