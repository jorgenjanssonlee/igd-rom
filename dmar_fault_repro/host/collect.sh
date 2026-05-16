#!/usr/bin/env bash
# Snapshot host state for Intel IGD VFIO / DMAR troubleshooting and upstream bug reports.
# Run on the hypervisor (Unraid shell, Fedora live USB, etc.) before/during repro runs.

set -euo pipefail

IGD_BDF="${IGD_BDF:-}"

detect_igd_bdf() {
    if [[ -n "$IGD_BDF" ]]; then
        echo "$IGD_BDF"
        return
    fi
    # Prefer canonical Intel VGA at 00:02.0 when present
    if [[ -e /sys/bus/pci/devices/0000:00:02.0 ]]; then
        local c
        c=$(cat /sys/bus/pci/devices/0000:00:02.0/class 2>/dev/null || echo "")
        if [[ "${c:-}" == 0x030000 ]]; then
            echo "0000:00:02.0"
            return
        fi
    fi
    # Fallback: first Intel VGA device in sysfs
    local devpath vendor device
    for devpath in /sys/bus/pci/devices/*; do
        [[ -f "$devpath/vendor" ]] || continue
        vendor=$(cat "$devpath/vendor" 2>/dev/null || true)
        [[ "$vendor" == "0x8086" ]] || continue
        device=$(basename "$devpath")
        local cls
        cls=$(cat "$devpath/class" 2>/dev/null || echo "")
        if [[ "${cls:-}" == 0x030000 ]]; then
            echo "$device"
            return
        fi
    done
    echo ""
}

banner() {
    echo ""
    echo "======== $* ========"
}

banner "timestamp"
date -Is 2>/dev/null || date

banner "uname"
uname -a

banner "/proc/cmdline"
cat /proc/cmdline 2>/dev/null || true

banner "kernel domain type hint (from current ring buffer)"
dmesg -T 2>/dev/null | grep -Fi 'iommu: Default domain type' | tail -5 || true

banner "IOMMU group domain types"
if compgen -G '/sys/kernel/iommu_groups/*/type' >/dev/null 2>&1; then
    for g in $(printf '%s\n' /sys/kernel/iommu_groups/*/type 2>/dev/null | sort -V); do
        printf '%s: %s\n' "$g" "$(cat "$g" 2>/dev/null)" || true
    done
else
    echo "(no /sys/kernel/iommu_groups/*/type — kernel too old or IOMMU off)"
fi

IGD_BDF="$(detect_igd_bdf)"
banner "detected IGD PCI BDF"
if [[ -z "$IGD_BDF" ]]; then
    echo "WARNING: Could not auto-detect Intel VGA device. Set IGD_BDF=0000:bus:dev.fn"
else
    echo "$IGD_BDF"
fi

if [[ -n "$IGD_BDF" ]]; then
    SYS_DEV="/sys/bus/pci/devices/$IGD_BDF"
    banner "IGD sysfs driver binding"
    if [[ -e "$SYS_DEV/driver" ]]; then
        readlink -f "$SYS_DEV/driver" || readlink "$SYS_DEV/driver" || true
    else
        echo "(no driver bound)"
    fi

    banner "IGD iommu_group/reserved_regions"
    if [[ -e "$SYS_DEV/iommu_group/reserved_regions" ]]; then
        cat "$SYS_DEV/iommu_group/reserved_regions"
    else
        echo "(reserved_regions missing)"
    fi

    banner "IGD iommu_group/type"
    if [[ -e "$SYS_DEV/iommu_group/type" ]]; then
        cat "$SYS_DEV/iommu_group/type"
    else
        echo "(type missing)"
    fi

    banner "lspci (IGD)"
    if command -v lspci >/dev/null 2>&1; then
        lspci -nn -s "$IGD_BDF" || true
        lspci -vvv -s "$IGD_BDF" 2>/dev/null | head -80 || true
    else
        echo "(lspci not installed)"
    fi
fi

banner "VFIO-related loaded modules (best-effort)"
if command -v lsmod >/dev/null 2>&1; then
    lsmod | grep -E '^vfio|^kvm|^iommu' || true
else
    echo "(lsmod missing)"
fi

banner "vfio_iommu_type1 parameters (if module loaded)"
for p in /sys/module/vfio_iommu_type1/parameters/*; do
    [[ -e "$p" ]] || continue
    printf '%s=%s\n' "$(basename "$p")" "$(cat "$p" 2>/dev/null)"
done 2>/dev/null || true

banner "QEMU version"
for q in qemu-system-x86_64 qemu-kvm /usr/local/sbin/qemu /usr/bin/qemu-system-x86_64; do
    if [[ -x "$q" ]] || command -v "$q" >/dev/null 2>&1; then
        "$q" --version 2>/dev/null | head -3 && break
    fi
done || echo "(qemu binary not found in PATH)"

banner "libvirt (virsh)"
if command -v virsh >/dev/null 2>&1; then
    virsh version 2>/dev/null || true
else
    echo "(virsh not installed)"
fi

banner "Recent DMAR / IOMMU / vfio lines from ring buffer (last ~120 matches)"
if command -v dmesg >/dev/null 2>&1; then
    dmesg -T 2>/dev/null | grep -Ei 'DMAR|dmar_fault|iommu:|vfio' | tail -120 || true
else
    echo "(dmesg missing)"
fi

banner "Boot DMAR RMRR line(s)"
if command -v dmesg >/dev/null 2>&1; then
    dmesg -T 2>/dev/null | grep -Fi 'DMAR: RMRR' || true
fi

banner "Optional: intel_iommu debugfs"
if [[ -d /sys/kernel/debug/iommu/intel ]] && compgen -G '/sys/kernel/debug/iommu/intel/*' >/dev/null 2>&1; then
    ls -la /sys/kernel/debug/iommu/intel 2>/dev/null || true
else
    echo "(debugfs not mounted or intel iommu debug empty — mount with: mount -t debugfs none /sys/kernel/debug)"
fi

banner "Done"
echo "Tip: redirect full output to a file, e.g.:"
echo "  $0 | tee \"artifacts/host-$(hostname)-$(date +%Y%m%d-%H%M%S).txt\""
