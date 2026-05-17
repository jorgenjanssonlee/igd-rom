# PROTOCOL — Intel IGD VFIO DMAR fault reproduction

Use this checklist together with [`host/collect.sh`](host/collect.sh), [`host/watch_dmar.sh`](host/watch_dmar.sh), and the guest scripts under [`guest-linux/`](guest-linux/) / [`guest-windows/`](guest-windows/).

## Goals

1. Produce **repeatable host-side** logs matching:
   - `DMAR: [DMA Read NO_PASID] Request device [XX:YY.Z] fault addr 0x........ [fault reason 0x06] PTE Read access is not set`
   - Fault addresses typically inside the ACPI **RMRR** range reported at boot (`DMAR: RMRR base: ... end: ...`).
2. Prefer triggering from a **Linux guest** (mesa/i915 + KMS) before relying on Windows-only behaviour.
3. Archive artefacts under `artifacts/<host>-<guest>-<YYYYMMDD>/` (create directory before runs).

## Important caveats

- **Expected benign faults:** QEMU documents a small burst of DMAR faults right after VM start for IGD assignment (`docs/igd-assign.txt`). Do not confuse those with sustained faulting during workloads.
- **Do not trust `grep -c` on full `dmesg`** for intermittent bursts — the kernel rate-limits duplicate fault logs (`callbacks suppressed`). Capture **timestamped slices** during each phase instead:
  ```bash
  dmesg -T > "artifacts/run-phaseA-end.txt"
  ```
  Or copy matching lines from `journalctl -k --since '10 minutes ago'`.

## Variable matrix (record per run)

| Field | Example |
|-------|---------|
| Host OS / kernel | Unraid 7.2.x `uname -r`, or Fedora Live |
| `/proc/cmdline` | `intel_iommu=on iommu=nopt ...` |
| IOMMU domain type | `cat /sys/bus/pci/devices/0000:00:02.0/iommu_group/type` |
| QEMU / libvirt | from `collect.sh` |
| Guest OS | Fedora Xfce Spin (install to VM disk — see README) / Win11 25H2 |
| Guest workload phase | A/B/C/D below |

---

## Linux guest image (recommended)

Use **[Fedora Xfce Spin](https://fedoraproject.org/spins/xfce)** amd64 ISO in the VM (filename includes `-Live-`; that is normal — the ISO both boots a live session **and** installs to disk), then **Install to Disk** during setup so packages and soak scripts persist across reboots. ISOs live under Fedora’s **[releases download tree](https://dl.fedoraproject.org/pub/fedora/linux/releases/)** (pick the current release → `Spins/x86_64/iso/` → Xfce `.iso`).

After first boot: `sudo dnf install -y mpv xdotool xset` for [`guest-linux/repro.sh`](guest-linux/repro.sh). (Older docs mentioned `xorg-x11-server-utils`; on Fedora 44 **`xset` is its own package**.) For Phase B’s default H.264 network sample, enable **RPM Fusion (free)** and install full **`ffmpeg`** (typically `sudo dnf install -y ffmpeg --allowerasing` to replace **`ffmpeg-free`**) — see [`README.md` — Codec stack for Phase B (Fedora)](README.md#codec-stack-for-phase-b-fedora). **SSH from another machine:** install **`openssh-server`**, enable **`sshd`**, then before Phases **A–C** over SSH export **`DISPLAY=:0`** and **`XAUTHORITY`** for the logged-in X11 user — see [`README.md` — SSH from another machine (optional)](README.md#ssh-from-another-machine-optional).

**Alternative:** Debian Live Xfce amd64 hybrid from [Debian CD/live](https://www.debian.org/CD/live/).

---

## Phase 0 — Host baseline

On the **hypervisor**, before starting the guest workload window:

```bash
cd dmar_fault_repro/host
chmod +x collect.sh watch_dmar.sh
./collect.sh | tee ../artifacts/<label>-baseline.txt
```

Optional second terminal:

```bash
./watch_dmar.sh --tee ../artifacts/<label>-live.log
```

---

## Phase 1 — Guest cold idle (5–10 minutes)

1. Start VM; wait until guest desktop/session is usable.
2. Do **not** run repro scripts yet.
3. On host, note whether only the short startup burst appears vs continuous faults.

---

## Phase A — Display power cycling (high priority)

Symptoms have correlated with **DPMS / panel sleep / resume** even when Windows DWM overlays are restricted — repeat under Linux first.

**Linux guest** (`guest-linux/repro.sh phase-a` or manual):

- Requires X11/Wayland session with `DISPLAY` set (script warns if missing).
- Script loops `xset dpms force off` / `suspend` / `on` with delays.

**Windows guest** (`guest-windows/repro.ps1 -Phase A`):

- Uses SendMessage display-off hack or guided manual lock/display-off steps documented in script output.

**Host:** After each cycle, grab:

```bash
dmesg -T | grep -E 'DMAR|dmar_fault' | tail -50
```

---

## Phase B — Scanout / video workload

Stress decode + composition paths that hit the display engine.

**Linux:**

- Preferred: `mpv --vo=gpu` or `ffplay` fullscreen/windowed (script tries `mpv`, then `ffplay`).
- Install hints (Fedora): `dnf install mpv`; (Debian): `apt install mpv`.

**Windows:**

- Bounded playback via Films & TV, VLC, or Edge — script prints suggestions.

---

## Phase C — Cursor churn

Rapid cursor updates may shift allocations in stolen-memory-related regions over time.

**Linux:** Script uses `xdotool` mouse moves when installed (`dnf install xdotool`).

**Windows:** Script runs a short SendInput jitter loop.

---

## Phase D — Soak / allocator drift

Some setups fault only after **multi-hour** uptime:

1. Alternate Phase A → idle → Phase B → idle every N minutes for **2–6 hours**, or overnight.
2. Record wall-clock **start/end** and guest uptime.
3. If nothing triggers quickly, this phase is **normal** — still file-worthy if intermittent.

---

## Pass / fail for packaging an upstream bug

**Minimum:**

- At least one host log excerpt showing sustained `fault reason 0x06` correlated with a documented phase (ideally Phase A or B on **Linux guest**).
- `collect.sh` output from same host configuration.

**Strong:**

- Same signature reproduced on **vanilla distro kernel** (live USB host) + Linux guest (Priority B in README).

---

## Ordering (recommended)

1. **Priority A:** Linux guest on current hypervisor — Phases 1 → A → B → C → D as needed.
2. **Priority B:** Same VM XML / ROM on Fedora/Ubuntu live host — repeat Phase A–D once Linux guest repro is understood.
3. **Priority C:** Windows guest logs as supplemental evidence — [`KERNEL_BUG_TEMPLATE.md`](KERNEL_BUG_TEMPLATE.md).
