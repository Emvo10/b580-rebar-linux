# Intel Arc B580 ReBAR workaround for Linux

A small Linux userspace workaround that can turn an Intel Arc B580 from a **256 MB BAR** into a **16 GB BAR aperture**, allowing the `xe` driver to expose essentially all usable VRAM as CPU-accessible memory on compatible older systems.

It does **not** flash or modify the BIOS/VBIOS.

## Quick start — Bazzite

If you use **Bazzite** and have an Intel Arc B580, you do not need to find PCI addresses or edit the script manually.

```bash
git clone https://github.com/Emvo10/b580-rebar-linux.git
cd b580-rebar-linux
sudo ./install.sh
systemctl reboot
```

The installer detects Bazzite/rpm-ostree systems and automatically adds `pci=realloc` if it is missing. It then installs and enables the boot service.

After reboot, verify:

```bash
sudo b580-rebar --check
```

Expected result:

```text
Result: ReBAR 16 GB ACTIVE
```

You can also verify it in **LACT**. A successful B580 setup should show **Resizable BAR: Enabled** and roughly **12 GB CPU Accessible VRAM** on the 12 GB model.

If the installer cannot safely handle the machine automatically, it stops instead of guessing. See the detailed instructions and recovery section below.

## Confirmed working

Tested successfully on:

- Lenovo ThinkStation P520
- Intel Arc B580 12 GB (`8086:e20b`)
- Bazzite 44
- Linux `7.2.1-ogc4.1.fc44`
- Intel `xe` driver

Before:

```text
BAR 2: current size: 256MB
CPU accessible VRAM: 256 MiB
```

After:

```text
Region 2: ... [size=16G]
BAR 2: current size: 16GB
CPU accessible VRAM: ~11.93 GiB
```

LACT reports the full usable VRAM as CPU-accessible.

## Important: this is hardware-dependent

This cannot be guaranteed to work on every motherboard. The platform must provide enough **64-bit PCI/MMIO address space above 4 GB** for a 16 GB BAR. If your firmware exposes **Above 4G Decoding**, enable it. CSM should normally be disabled / UEFI boot should be used.

The script deliberately aborts if the auto-detected PCI root-port branch contains an unrelated endpoint such as NVMe, networking or USB. Removing a shared root port while the system is running could disconnect those devices.

The workaround targets **Intel Arc B580 only**. It is not a generic ReBAR enabler for other GPUs.

## Requirements

- Intel Arc B580 (`8086:e20b`)
- Linux with Intel `xe` driver (kernel 6.12+ is a sensible baseline)
- `pciutils` (`lspci` and `setpci`)
- systemd
- kernel parameter: `pci=realloc`
- enough 64-bit PCI/MMIO space above 4 GB

## 1. Add `pci=realloc`

First check:

```bash
cat /proc/cmdline
```

If `pci=realloc` is already present, continue to installation.

### Bazzite / rpm-ostree systems

The recommended Bazzite path is the **Quick start** above: `install.sh` adds `pci=realloc` automatically when it is missing.

To add it manually instead:

```bash
sudo rpm-ostree kargs --append-if-missing="pci=realloc"
systemctl reboot
```

### Fedora/RHEL systems with `grubby`

```bash
sudo grubby --update-kernel=ALL --args="pci=realloc"
systemctl reboot
```

### Debian/Ubuntu with GRUB

Add `pci=realloc` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then run:

```bash
sudo update-grub
systemctl reboot
```

After reboot, confirm:

```bash
cat /proc/cmdline
```

## 2. Install

Clone/download this repository, enter its directory, then:

```bash
sudo ./install.sh
```

The installer **does not start the workaround immediately**, because unbinding the GPU from a running desktop can terminate the graphical session.

Reboot:

```bash
systemctl reboot
```

The service runs before the display manager and applies the resize during boot.

## 3. Verify

Easy check:

```bash
sudo b580-rebar --check
```

Expected result:

```text
Result: ReBAR 16 GB ACTIVE
```

Raw PCI check:

```bash
GPU=$(lspci -D -d 8086:e20b | awk 'NR==1 {print $1}')
sudo lspci -vv -s "$GPU" | grep -E 'Region 2|Resizable BAR' -A2
```

Expected:

```text
Region 2: Memory at ... [size=16G]
BAR 2: current size: 16GB
```

Driver check:

```bash
sudo dmesg | grep -iE 'xe.*(BAR|VRAM|resize)'
```

On a 12 GB B580, a successful setup should show roughly **11.9 GiB CPU-accessible VRAM** (the small difference is reserved/stolen memory).

Service status and logs:

```bash
systemctl status b580-rebar.service --no-pager -l
sudo journalctl -u b580-rebar.service -b --no-pager
```

## How it works

At boot the script:

1. Finds the B580 automatically by PCI ID.
2. Checks that the GPU advertises a 16 GB ReBAR size.
3. Finds the upstream PCI root port automatically.
4. Refuses to continue if that root-port branch contains unrelated endpoint devices.
5. Unbinds `xe` and the B580 HDMI/DP audio endpoint if already bound.
6. Changes the B580 ReBAR BAR2 size field to **16 GB** using `setpci`.
7. Removes and rescans the upstream PCI branch so Linux can re-lay the bridge resources using `pci=realloc`.
8. Verifies that BAR2 is actually 16 GB.

The actual B580 VRAM remains 12 GB. The 16 GB value is the PCI BAR aperture size.

## Advanced overrides

The script normally auto-detects the GPU and root port. For unusual PCI topologies you can create:

```text
/etc/default/b580-rebar
```

with, for example:

```bash
B580_GPU=0000:67:00.0
B580_ROOT_PORT=0000:64:00.0
```

Only use manual overrides if you have checked the topology with:

```bash
lspci -t -D
```

Do not point `B580_ROOT_PORT` at a branch containing storage, networking, USB or other unrelated devices.

## Uninstall

From the repository directory:

```bash
sudo ./uninstall.sh
systemctl reboot
```

The uninstaller intentionally does **not** remove `pci=realloc`, because changing kernel arguments is distro/bootloader-specific. Remove it separately if you no longer need it.

For Bazzite/rpm-ostree:

```bash
sudo rpm-ostree kargs --delete="pci=realloc"
systemctl reboot
```

## Recovery

If a particular machine does not come back to a graphical login after enabling the service, boot to a TTY/recovery environment and disable it:

```bash
sudo systemctl disable b580-rebar.service
sudo rm -f /etc/systemd/system/b580-rebar.service
sudo systemctl daemon-reload
systemctl reboot
```

You can also temporarily mask the service from the kernel command line with:

```text
systemd.mask=b580-rebar.service
```

No BIOS or VBIOS changes are made by this project; a normal reboot resets the GPU's PCI configuration.

## Why this exists

On some older workstations the B580 advertises ReBAR sizes up to 16 GB, and the Linux `xe` driver attempts to resize from 256 MiB to 16 GiB, but the attempt fails with `-ENOSPC` because the existing bridge windows are too small. Re-enumerating the PCI branch after selecting the 16 GB BAR lets Linux reallocate those bridge resources on compatible platforms.

## Credits

This project is based on the Linux B580 `setpci` + PCI remove/rescan method documented by Anders Evenrud for the Supermicro H11SSL-i. The systemd packaging, safety checks, automatic detection and Bazzite-tested setup here are a generalized implementation of that approach.

Upstream reference:

https://gist.github.com/andersevenrud/eec93e9151117bc0d6b6133b40eaffa5

## Disclaimer

This writes to PCI configuration space and temporarily removes/re-enumerates a PCIe branch. It is much less invasive than flashing modified firmware, but it is still an unsupported workaround. Test carefully and keep a recovery path available.
