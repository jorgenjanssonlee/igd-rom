# DMAR fault reproduction harness (Intel IGD VFIO)

This directory contains **host-side** and **guest-side** helpers to capture reproducible **VT-d DMAR** fault logs for upstream Linux kernel reports. It pairs with project notes in [`../Host and VM config/troubleshooting.md`](../Host%20and%20VM%20config/troubleshooting.md).

## Contents

| Path                                                 | Role                                                          |
| ---------------------------------------------------- | ------------------------------------------------------------- |
| [`PROTOCOL.md`](PROTOCOL.md)                         | Phases, ordering, caveats, pass/fail criteria                 |
| [`KERNEL_BUG_TEMPLATE.md`](KERNEL_BUG_TEMPLATE.md)   | Paste-ready bug report sections + attachment checklist        |
| [`host/collect.sh`](host/collect.sh)                 | One-shot hypervisor snapshot (IOMMU, RMRR hints, VFIO, dmesg) |
| [`host/watch_dmar.sh`](host/watch_dmar.sh)           | Live `journalctl` / `dmesg -w` filter for DMAR lines          |
| [`guest-linux/repro.sh`](guest-linux/repro.sh)       | Linux guest workloads (DPMS / video / cursor)                 |
| [`guest-windows/repro.ps1`](guest-windows/repro.ps1) | Windows guest workload hints + registry probes                |
| [`artifacts/`](artifacts/)                           | Create per-run logs: `artifacts/<host>-<guest>-<date>/`       |

## Recommended Linux guest: Fedora Xfce Spin (install to disk)

For DRM/KMS/i915 display paths (DPMS, GPU video output, cursor churn), use a **desktop** guest. The default recommendation is **Fedora Xfce Spin**:

- Current Mesa/kernel stack, few surprises for Intel i915 passthrough.
- The filename contains **`-Live-`** — that only means “bootable desktop from ISO”; **the same ISO is used to install to disk.** After boot from ISO, choose *Install Fedora* / *Install to Hard Drive*.
- Boots from ISO in the VM; **install to the VM disk** for repeatable tooling and long soak runs (live sessions reset every reboot).

**Download (pick current release; amd64/x86_64 ISO):**

- Spin overview: [Fedora Xfce Spin](https://fedoraproject.org/spins/xfce)
- ISO files: browse [Fedora releases — Spins x86_64 iso](https://dl.fedoraproject.org/pub/fedora/linux/releases/) (open the newest version folder, then `Spins/x86_64/iso/` and fetch the Xfce `.iso`)

After install, install optional deps used by [`guest-linux/repro.sh`](guest-linux/repro.sh):

```bash
sudo dnf install -y mpv xdotool xset
```

(Optional: `sudo dnf install -y xrandr` — useful manually; Phase A uses `xset dpms`.)

### Alternatives (if you prefer a smaller ISO)

- **Debian Live Xfce** amd64 hybrid: [Debian Live images](https://www.debian.org/CD/live/) — older Mesa/kernel by default, still valid for baseline comparison.

## Quick start (hypervisor)

```bash
cd dmar_fault_repro
mkdir -p artifacts/run-001
chmod +x host/collect.sh host/watch_dmar.sh

# Terminal 1
./host/collect.sh | tee artifacts/run-001/baseline.txt

# Terminal 2 (optional)
./host/watch_dmar.sh --tee artifacts/run-001/live.log
```

Start the VM; in the **Linux guest** (preferred):

```bash
chmod +x repro.sh   # path: guest-linux/repro.sh copied in, or mount this repo
./guest-linux/repro.sh probe
./guest-linux/repro.sh phase-a
```

For Phase B **without network**, copy any short MP4 locally and run:

```bash
REPRO_VIDEO=/path/to/file.mp4 ./guest-linux/repro.sh phase-b
```

After each phase on the host:

```bash
dmesg -T | grep -E 'DMAR|dmar_fault' | tail -80 | tee artifacts/run-001/after-phase-a.txt
```

## Baseline VM / IGD XML

Use the same VFIO / IGD settings you already validated, e.g. [`../Host and VM config/Win11.xml`](../Host%20and%20VM%20config/Win11.xml) — in particular:

- `vfio-pci` for `00:02.0`
- `rom` / `Universal_noGOP_igd.rom` (or equivalent for your UPT workflow)
- `x-igd-opregion=true` qemu override where required

Spice/VNC vs physical DisplayPort does not change host DMAR logging, but your display-sleep testing may need **physical** or **Guest** DPMS — see PROTOCOL Phase A.

## Live USB host (narrow Unraid-specific issues)

Goal: reproduce the **same DMAR signature** with a mainstream kernel + QEMU/libvirt.

1. Boot **Fedora Workstation Live** or **Ubuntu Desktop** with IOMMU enabled in firmware.
2. Load modules and bind GPU (example — **adjust PCI BDF**):

   ```bash
   sudo modprobe vfio vfio_pci vfio_iommu_type1
   echo "8086 xxxx" | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id   # replace with your iGPU vendor:device from lspci -nn
   echo 0000:00:02.0 | sudo tee /sys/bus/pci/devices/0000:00:02.0/driver/unbind 2>/dev/null || true
   echo 0000:00:02.0 | sudo tee /sys/bus/pci/drivers/vfio-pci/bind
   ```

   Alternatively use **libvirt helper** / `virt-manager` device assignment if available.

3. Copy your VM XML + ROM paths; run `./host/collect.sh` on **both** Unraid and live host and diff `cmdline`, IOMMU `type`, kernel version.

Unraid notes: avoid loading `i915` on the host for the passthrough device; keep `intel_iommu=on` and your chosen `iommu=nopt` / `iommu=pt` policy documented in the bug report.

## Windows guest

From an elevated PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd <path>\dmar_fault_repro\guest-windows
.\repro.ps1 -Phase Probe
.\repro.ps1 -Phase A
```

Windows is **supplemental** for upstream; still useful for correlation with real-world workloads.

## Artefact layout (suggested)

```
artifacts/<host>-<guest>-20260516/
  baseline.txt          # collect.sh
  live.log              # optional watch_dmar.sh
  after-phase-a.txt     # dmesg slices
  repro-notes.md        # wall clock, firmware, guest commands
```

## See also

- [`PROTOCOL.md`](PROTOCOL.md) — full phased procedure
- [`KERNEL_BUG_TEMPLATE.md`](KERNEL_BUG_TEMPLATE.md) — filing the bug
