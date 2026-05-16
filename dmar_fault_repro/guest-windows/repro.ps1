# Guest-side reproduction helper for Windows (Intel IGD VM).
# Run *inside* the Windows guest as Administrator (recommended for registry probes).
# Phases mirror dmar_fault_repro/PROTOCOL.md.

param(
    [ValidateSet('All', 'Probe', 'A', 'B', 'C', 'D')]
    [string]$Phase = 'All'
)

function Log($m) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format o), $m)
}

function Reg-Probe {
    Log "Registry probes (informational)"
    $dwm = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'
    if (Test-Path $dwm) {
        Get-ItemProperty -Path $dwm -Name 'OverlayTestMode' -ErrorAction SilentlyContinue |
            Format-List | Out-String | Write-Host
    } else {
        Write-Host "No Dwm key (OverlayTestMode not set)"
    }
    $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if (Test-Path $cls) {
        Get-ChildItem $cls | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $p = Join-Path $cls $_.PSChildName
            Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
                Select-Object PSChildName, PanelSelfRefreshEnable, HwSchMode |
                Format-Table -AutoSize
        }
    }
}

function Phase-A {
    Log "Phase A — Display power / lock hints"
    Log "Automating display-off via WM_SYSCOMMAND (may not affect all setups)."
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class D {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
'@
    # SC_MONITORPOWER: low-power / off — restore by mouse move or timeout policy
    try {
        [D]::SendMessage([IntPtr]::Zero, 0x0112, [IntPtr]::new(0xF170), [IntPtr]::new(2)) | Out-Null
        Start-Sleep -Seconds 4
        # Wake hint
        Add-Type @'
using System.Runtime.InteropServices;
public class M {
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
}
'@
        [M]::mouse_event(0x0001, 5, 5, 0, 0)
        Start-Sleep -Milliseconds 500
        [M]::mouse_event(0x0001, -5, -5, 0, 0)
    } catch {
        Log "SendMessage path failed: $($_.Exception.Message)"
    }
    Log "Optional manual steps: Win+L lock; adjust monitor sleep in Settings."
}

function Phase-B {
    Log "Phase B — bounded playback hints"
    Log "Play any short H.264/VP9 clip in Films & TV, VLC, or Edge (windowed then fullscreen)."
    $clip = "$env:TEMP\dmar_repro_sample.mp4"
    if (-not (Test-Path $clip)) {
        Log "No bundled video. Open YouTube or local file manually for 60–120 seconds."
    }
}

function Phase-C {
    Log "Phase C — cursor churn (SendInput)"
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class C {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
}
'@
    for ($i = 0; $i -lt 300; $i++) {
        $x = 200 + ($i % 600)
        $y = 200 + ($i % 400)
        [void][C]::SetCursorPos($x, $y)
        Start-Sleep -Milliseconds 20
    }
}

function Phase-D {
    Log "Phase D — soak: alternate A -> sleep -> manual video; see PROTOCOL.md"
}

switch ($Phase) {
    'Probe' { Reg-Probe }
    'A' { Phase-A }
    'B' { Phase-B }
    'C' { Phase-C }
    'D' { Phase-D }
    'All' {
        Reg-Probe
        Phase-A
        Phase-B
        Phase-C
        Log "Done All. Long soak: run with -Phase D and follow PROTOCOL.md"
    }
}
