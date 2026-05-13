<#
.SYNOPSIS
  WSL Zombie Killer - Universal Edition
  Detects and terminates zombie wslservice.exe processes.
   
   DETECTION (multi-layer, no false positives):
     1. vmmem / VmmemWSL exists → WSL VM is alive → SKIP (strongest signal)
     2. wslservice age < 120s → still booting → SKIP (grace period)
     3. wslservice has child processes → normal WSL → SKIP
     4. LxssManager "Running" → definitely not zombie → SKIP
     5. Double-check after 3s delay before killing
   
  KILL (auto-fallback):
    1. Backstab.exe (kernel driver, Microsoft-signed)
    2. taskkill /F
    3. Stop-Process -Force
   
  SCHEDULED TASK: KillWSLZombie
    BootTrigger + LogonTrigger, script loops internally every 60s
   
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

function Show-Help {
    Write-Host @"
WSL Zombie Killer - Universal Edition

USAGE:
  powershell -File kill-zombie.ps1 -Install       Install
  powershell -File kill-zombie.ps1 -Uninstall     Uninstall
  powershell -File kill-zombie.ps1                Run once

DETECTION (safe):
   vmmem / VmmemWSL exists → WSL VM alive → skip
   wslservice age < 120s → still booting → skip
   wslservice has children → normal → skip
   Age > 120s + no vmmem + no children → zombie
   Double-check after 3s before killing

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

    # Register scheduled task with dynamically generated XML
    $ps1Path = "$toolsDir\kill-zombie.ps1"
    # NOTE: BootTrigger + LogonTrigger for reliability:
    #   - BootTrigger: fires on system startup (needs LogonType=S4U or Password for SYSTEM context)
    #   - LogonTrigger: fires when user logs in (InteractiveToken works here)
    #   - Script loops internally with while($true), so it only needs to be started once
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Auto-kill zombie wslservice.exe. Triggers at boot + user logon, loops internally.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT1M</Delay>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>S4U</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Enabled>true</Enabled>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowStartOnDemand>true</AllowStartOnDemand>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoLogo -NoProfile -ExecutionPolicy Bypass -File "$ps1Path"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $tempXml = "$toolsDir\task-temp.xml"
    Set-Content $tempXml $taskXml -Encoding Unicode
    schtasks /Create /TN $taskName /XML $tempXml /F
    Remove-Item $tempXml -Force -ErrorAction SilentlyContinue
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

    # Safety 1: Vmmem process exists = WSL VM is alive, NOT a zombie
    # Some systems name it "VmmemWSL", others just "vmmem" (Win10 22H2)
    if ((Get-Process VmmemWSL -ErrorAction SilentlyContinue) -or (Get-Process vmmem -ErrorAction SilentlyContinue)) { return $false }

    # Safety 2: wslservice is very young (< 120s) — WSL may still be booting, vmmem hasn't spawned yet
    # Give it more time before judging
    $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -Property CreationDate -ErrorAction SilentlyContinue
    if ($ci -and $ci.CreationDate) {
        try {
            $ts = [DateTime]::ParseExact($ci.CreationDate.Substring(0,14), 'yyyyMMddHHmmss', $null)
            $procAge = (Get-Date) - $ts
            if ($procAge.TotalSeconds -lt 120) { return $false }
        } catch {}
    }

    # Safety 3: wslservice with child processes = normal WSL running
    # Orphaned wslservice (no children) = likely zombie
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
    if ($children) { return $false }

    # Check LxssManager service state (supplementary, not primary — service may show
    # Stopped even when WSL is running on some Win10 systems)
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='LxssManager'" -ErrorAction SilentlyContinue
    # Only reject if service says Running (definitely not zombie)
    if ($svc -and $svc.State -eq "Running") { return $false }
    # Do NOT require Stopped — on some systems LxssManager is always "Stopped"

    # Double-check after 3s delay (all primary checks)
    Start-Sleep 3
    if ((Get-Process VmmemWSL -ErrorAction SilentlyContinue) -or (Get-Process vmmem -ErrorAction SilentlyContinue)) { return $false }
    $proc2 = Get-Process wslservice -ErrorAction SilentlyContinue
    if (-not $proc2) { return $false }
    $children2 = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc2.Id)" -ErrorAction SilentlyContinue
    if ($children2) { return $false }

    return $true
}

# ── Kill (multi-method) ──

function Invoke-KillZombie {
    param($Proc)
    $ageStr = ""
    try {
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$($Proc.Id)" -Property CreationDate -EA 0
        if ($ci -and $ci.CreationDate) {
            $ts = [DateTime]::ParseExact($ci.CreationDate.Substring(0,14), 'yyyyMMddHHmmss', $null)
            $ageStr = ", age $([math]::Round(((Get-Date) - $ts).TotalMinutes,1)) min"
        }
    } catch {}
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Detected zombie wslservice.exe PID $($Proc.Id)$ageStr" | Out-File $logPath -Append

    # Method 1: Backstab (set working dir so it can write driver)
    if (Test-Path $backstabPath) {
        Push-Location $toolsDir
        try {
            for ($i = 0; $i -lt 3; $i++) {
                & $backstabPath -n wslservice.exe -k -d "$toolsDir\"
                Start-Sleep 2
                if (-not (Get-Process wslservice -EA 0)) { break }
            }
        } finally { Pop-Location }
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

# Internal loop: check every 60s, kill any zombie, keep running forever
while ($true) {
    if (Test-WSLZombie) {
        $proc = Get-Process wslservice -EA 0
        if ($proc) { Invoke-KillZombie $proc }
    }
    Start-Sleep 60
}
