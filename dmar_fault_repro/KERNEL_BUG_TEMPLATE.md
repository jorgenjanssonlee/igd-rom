# Kernel bug report template — Intel IGD VFIO DMAR faults (fault reason 0x06)

Copy sections into Bugzilla / email as appropriate. Replace `(...)`.

---

## Summary / Title

```
Intel VT-d DMAR faults (fault reason 0x06, PTE read not set) on Intel IGD ([PCI]) under VFIO passthrough when guest uses display engine / DRM (RMRR GSM-range DMA reads)
```

---

## Hardware

- Motherboard / firmware: (...)
- CPU: (...) Gen / stepping
- iGPU PCI ID: (...) — output of `lspci -nn -s XX:YY.Z`
- RAM / monitors / cabling (optional): (...)

---

## Software — Host

- Distribution / purpose: e.g. Unraid 7.x / Fedora Live 41 / Ubuntu Live 24.04
- Kernel: output of `uname -r`
- Full kernel cmdline: `/proc/cmdline`
- IOMMU domain type for IGD group:
  ```text
  cat /sys/bus/pci/devices/0000:__/__.__/iommu_group/type
  ```
- QEMU version / libvirt version (if applicable): (...)

Attach **`collect.sh` output** from [`host/collect.sh`](host/collect.sh).

---

## Software — Guest

- OS + version: e.g. Fedora 41 Workstation / Windows 11 25H2
- Kernel (Linux guest): `uname -r`
- Mesa / intel driver notes (Linux): `glxinfo -B` optional

Describe minimal repro steps (numbered):

1. Bind IGD to vfio-pci; attach to VM as (overview XML / QEMU args summary).
2. Start VM with ROM (...) and QEMU flags (...) — attach snippet if possible.
3. In guest: run `guest-linux/repro.sh phase-a` OR equivalent manual steps from PROTOCOL.md Phase A/B.
4. On host within (...) minutes of workload: DMAR faults appear as below.

---

## Observed behaviour — Host logs

Paste representative lines:

```text
DMAR: [DMA Read NO_PASID] Request device [XX:YY.Z] fault addr 0x........ [fault reason 0x06] PTE Read access is not set
```

Include boot-time RMRR line:

```text
DMAR: RMRR base: 0x........ end: 0x........
```

Note correlation (DPMS wake, video playback, idle soak, etc.).

---

## Hypothesis (careful wording)

**Symptom-level:** DMAR faults indicate device `[XX:YY.Z]` attempted DMA reads inside the ACPI RMRR region for integrated graphics while assigned via VFIO; IOMMU reports PTE exists but **read permission not set** (fault reason `0x06`).

**Hypothesis:** Behaviour is consistent with incorrect mapping permissions for portions of RMRR/GSM when programming Intel IOMMU page tables for the VFIO domain — **requires confirmation** via developer inspection / bisection (`drivers/iommu/intel/iommu.c`, VFIO interaction).

Avoid asserting a specific bug without bisect ack.

---

## Bisection / debug

Offer to bisect between (...) kernels if maintainers provide guidance.

Avoid enabling noisy `intel_iommu` debug unless requested.

---

## Attachments checklist

| File | Description |
|------|-------------|
| `collect-<host>-*.txt` | Output of `host/collect.sh` |
| `dmesg-phase-*.txt` | Timestamped host ring-buffer excerpts per PROTOCOL phase |
| `guest-linux/repro.sh` log | If captured |
| Minimal VM XML fragment | VFIO hostdev + qemu overrides for IGD |
| Reference | QEMU https://gitlab.com/qemu-project/qemu/-/work_items/3481 |

---

## Routing (update at filing time)

- Prefer **Linux Kernel Bugzilla — IOMMU / VFIO** or maintainer-requested list.
- If redirected to **drm-intel**, include same hardware + guest DRM steps.
