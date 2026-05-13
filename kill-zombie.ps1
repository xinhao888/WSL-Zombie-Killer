<#
.SYNOPSIS
  WSL Zombie Killer - Universal Edition
  Detects and terminates zombie wslservice.exe processes.
  
  DETECTION (safe, triple-checked):
    1. wslservice.exe running + LxssManager "Stopped"
       AND process age > 60 seconds (excludes clean shutdown)
    2. Same as above + double-check after 3s delay
  
  KILL (auto-fallback):
    1. Backstab.exe (kernel driver, most reliable)
    2. taskkill /F
    3. Stop-Process -Force
  
  SCHEDULED TASK: KillWSLZombie
    Triggers at boot + on LxssManager start
    Runs every 30 seconds, stops after successful kill
  
.NOTES
  Author: XinHaoZiDongHua
  Repository: https://github.com/xinhao888/WSL-Zombie-Killer
  Dependencies: Backstab (github.com/Yaxser/Backstab)
#>

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Help
)

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backstabUrl = "https://github.com/Yaxser/Backstab/releases/download/v1.0.1-beta/Backstab64.exe"
$backstabPath = "$toolsDir\Backstab64.exe"
$taskName = "KillWSLZombie"
$logPath = "$toolsDir\zombie-kill.log"
$xmlPath = "$toolsDir\zombie-killer-task.xml"

# Min age in seconds for a process to be considered a zombie
# (excludes clean shutdown transients)
$minProcAge = 60

function Show-Help {
    Write-Host @"
WSL Zombie Killer - Universal Edition

USAGE:
  powershell -File kill-zombie.ps1 -Install       Install
  powershell -File kill-zombie.ps1 -Uninstall     Uninstall
  powershell -File kill-zombie.ps1                Run once

DETECTION (safe):
  wslservice.exe running >60s + LxssManager "Stopped"
  + double-check 3s later before killing
  (Only "Stopped", not "Stop Pending" — no false positives)

KILL METHODS (auto-fallback):
  1. Backstab (kernel driver)
  2. taskkill /F
  3. Stop-Process -Force

LOG: $logPath
"@
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-Tool {
    if (-not (Test-IsAdmin)) { Write-Error "Admin required."; return }

    schtasks /Query /TN $taskName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Warning "Task '$taskName' already exists. Uninstall first."; return }

    # Add Defender exclusion
    try { Add-MpPreference -ExclusionPath $toolsDir -ErrorAction SilentlyContinue } catch {}

    # Download Backstab if missing
    if (-not (Test-Path $backstabPath)) {
        Write-Host "Downloading Backstab from GitHub..."
        try { curl.exe -L -o $backstabPath $backstabUrl --connect-timeout 30 --max-time 120 } catch {}
        if (-not (Test-Path $backstabPath)) {
            Write-Warning "Download failed. Place Backstab64.exe manually in: $toolsDir"
            Write-Warning "Download: $backstabUrl"
        }
    }

    # Register scheduled task
    schtasks /Create /TN $taskName /XML $xmlPath /F
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installed successfully."
    } else {
        Write-Error "Task creation failed. Run as Administrator."
    }
}

function Uninstall-Tool {
    if (-not (Test-IsAdmin)) { Write-Error "Admin required."; return }
    schtasks /Delete /TN $taskName /F 2>$null
    Write-Host "Uninstalled."
}

# ── Detection (safe): returns $true only if zombie confirmed ──

function Test-WSLZombie {
    $proc = Get-Process wslservice -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }

    # Safety: require process StartTime (some system processes might not report it)
    if (-not $proc.StartTime) { return $false }

    # Safety: process must have been running for > $minProcAge seconds
    # This excludes transient states during clean shutdown
    $procAge = (Get-Date) - $proc.StartTime
    if ($procAge.TotalSeconds -lt $minProcAge) { return $false }

    # Check LxssManager service state
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='LxssManager'" -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }

    # Only match "Stopped", NOT "Stop Pending" — avoids clean-shutdown false positive
    if ($svc.State -ne "Stopped") { return $false }

    # Double-check: wait 3s and verify again before committing to kill
    Start-Sleep 3
    $proc2 = Get-Process wslservice -ErrorAction SilentlyContinue
    $svc2 = Get-CimInstance -ClassName Win32_Service -Filter "Name='LxssManager'" -ErrorAction SilentlyContinue
    if ($proc2 -and $svc2 -and $svc2.State -eq "Stopped") {
        return $true
    }

    return $false
}

# ── Kill (multi-method) ──

function Invoke-KillZombie {
    param($Proc)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Detected zombie wslservice.exe PID $($Proc.Id), age $([math]::Round((Get-Date - $Proc.StartTime).TotalMinutes,1)) min" | Out-File $logPath -Append

    # Method 1: Backstab
    if (Test-Path $backstabPath) {
        for ($i = 0; $i -lt 3; $i++) {
            & $backstabPath -n wslservice.exe -k
            Start-Sleep 2
            if (-not (Get-Process wslservice -EA 0)) { break }
        }
        if (-not (Get-Process wslservice -EA 0)) {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Killed via Backstab" | Out-File $logPath -Append
            return $true
        }
    }

    # Method 2: taskkill
    taskkill /F /IM wslservice.exe 2>$null; Start-Sleep 1
    if (-not (Get-Process wslservice -EA 0)) {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Killed via taskkill" | Out-File $logPath -Append
        return $true
    }

    # Method 3: Stop-Process
    $p = Get-Process wslservice -EA 0
    if ($p) { Stop-Process $p.Id -Force -EA 0; Start-Sleep 1 }
    if (-not (Get-Process wslservice -EA 0)) {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Killed via Stop-Process" | Out-File $logPath -Append
        return $true
    }

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Failed to kill (needs manual)" | Out-File $logPath -Append
    return $false
}

# ── Main ──

if ($Help) { Show-Help; return }
if ($Install) { Install-Tool; return }
if ($Uninstall) { Uninstall-Tool; return }

if (Test-WSLZombie) {
    $proc = Get-Process wslservice -EA 0
    if ($proc -and (Invoke-KillZombie $proc)) {
        schtasks /End /TN $taskName *>$null
    }
}
