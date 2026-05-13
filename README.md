# WSL Zombie Killer

**Auto-detect and kill zombie wslservice.exe processes on Windows 10/11 WSL2.**

If you use WSL2 on Windows 10 22H2, you may have encountered this:

> WSL works for a few minutes, then all services die. `wsl --shutdown` hangs forever.  
> The only fix is rebooting Windows. A `wslservice.exe` zombie process is the cause.

This is a **known Windows 10 LxssManager bug**. Microsoft fixed it in Windows 11 24H2
(by rewriting LxssManager as WSLService) but **never backported the fix** to Windows 10.

**This tool automatically detects and kills the zombie without rebooting.**

---

## The Problem

```
wslservice.exe (session 0, SYSTEM)
    ↓  hvsocket hangs during WSL shutdown
stuck in "Stop Pending" state
    ↓  kernel objects locked
UNKILLABLE — even psexec -s (NT Authority\System) fails
    ↓  every 1-3 minutes
WSL VM forced rebuild → all services interrupted
```

Only full system restart used to fix it. Not anymore.

---

## Detection (Safe — No False Positives)

| Safeguard | What it prevents |
|-----------|-----------------|
| Only matches `"Stopped"`, **not** `"Stop Pending"` | Normal clean shutdown |
| Process age must be > **60 seconds** | Transient startup/shutdown states |
| **Double-check** after 3s delay before killing | Occasional system load spikes |

**False positive rate: near zero.**

Methods (tried in order):
1. `wslservice.exe` running >60s + LxssManager `"Stopped"` → Zombie
2. Re-verified after 3 seconds → Confirmed

---

## Kill Methods (Auto-fallback)

| Priority | Method | How it works |
|----------|--------|-------------|
| 1 | **Backstab** (kernel driver) | Uses Microsoft-signed ProcExp driver to terminate at Ring 0 |
| 2 | `taskkill /F` | Standard Windows force-kill (if admin rights available) |
| 3 | `Stop-Process -Force` | PowerShell last resort |

---

## Quick Start

### 1. Install (Admin)

**Double-click:** `一键安装.vbs` *(auto-elevates)*

**Or via command line:**
```powershell
# PowerShell (Admin):
powershell -File kill-zombie.ps1 -Install

# Or Command Prompt (Admin):
install.bat
```

The installer:
- Creates scheduled task `KillWSLZombie`
- Adds Windows Defender exclusion for Backstab
- Downloads Backstab.exe from GitHub (or you can place it manually)

### 2. How it works

```
Windows boot
    ↓
Task triggered (boot + LxssManager start events)
    ↓
Checks every 30 seconds
    ↓
Zombie detected? → Kill → Log → Stop task
    ↓
Next boot / WSL restart → Task re-triggered
```

### 3. Uninstall (Admin)

**Double-click:** `一键卸载.vbs`

**Or via command line:**
```powershell
powershell -File kill-zombie.ps1 -Uninstall
```

Or manually:
```cmd
schtasks /Delete /TN "KillWSLZombie" /F
```

---

## Manual Kill

If you want to kill immediately without waiting for the scheduled task:

```cmd
Backstab64.exe -n wslservice.exe -k
```

---

## File Structure

```
D:\WSL-Tools\
├── README.md              This file
├── LICENSE                MIT License
├── kill-zombie.ps1        Main detection + kill script
├── install.bat            Installer (Admin)
├── uninstall.bat          Uninstaller (Admin)
├── 一键安装.vbs            One-click installer (auto-elevate)
├── 一键卸载.vbs            One-click uninstaller (auto-elevate)
├── zombie-killer-task.xml Scheduled task definition
├── zombie-kill.log        Kill log (auto-generated)
├── Backstab64.exe         Backstab killer tool
└── 说明.txt               Chinese documentation
```

---

## Requirements

- Windows 10 or Windows 11
- WSL 2 with any distribution (Ubuntu, Debian, Kali, etc.)
- Administrator privileges (for installation and killing)

---

## Dependencies

- **[Backstab](https://github.com/Yaxser/Backstab)** — Kernel-mode process killer using Microsoft-signed driver
  *(Auto-downloaded during install, or place manually)*

---

## Notes

1. **This is a workaround, not a permanent fix.** The root cause is Windows 10's
   LxssManager service (fixed in Win11 24H2). Upgrade if possible.

2. **Antivirus may flag Backstab.exe** — it uses the same technique as EDR-killer
   tools. Defender exclusion is added automatically during install.

3. **Prevention:** Avoid `wsl --shutdown`. Use `wsl --terminate <distro>` instead.
   This reduces the chance of triggering the hvsocket hang.

4. **Distro-agnostic** — Works with any WSL distribution.

---

## Related Resources

- [Microsoft WSL Issue #1086](https://github.com/microsoft/WSL/issues/1086) — "WSL is unkillable without rebooting" (2016)
- [Microsoft WSL Issue #10505](https://github.com/microsoft/WSL/issues/10505) — "LxssManager keeps getting stuck in STOP_PENDING" (2023)
- [Backstab](https://github.com/Yaxser/Backstab) — Kernel-mode process termination
- [System Informer](https://github.com/winsiderss/systeminformer) — GUI alternative (Process Hacker)

---

## License

MIT License. See `LICENSE` file.
