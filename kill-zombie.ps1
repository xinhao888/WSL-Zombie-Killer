<#
.SYNOPSIS
  WSL Zombie Killer - Universal Edition
  Kills leftover wslservice processes and auto-starts WSL.

  TWO-PHASE (no zombie detection needed):
    BOOT:    if ANY WSL2-related processes exist → kill all → auto-start WSL (once per boot)
    INSTALL: same as BOOT, triggered on -Install (once)
    RUNTIME: if WSL2 NOT running (system-level) but wslservice exists → kill all

  KILL (multi-phase):
    1. taskkill /F /IM wslservice.exe (kills all by name)
    2. Stop-Process -Force (sweep remaining)
    3. Backstab.exe (kernel driver, for stubborn survivors)

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

$minProcAge = 60
$distroName = "Ubuntu-24.04"
$bootFlagFile = "$toolsDir\.boot-auto-started.txt"

function Add-Log {
    param($Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File $logPath -Append
}

function Get-ProcessAge {
    param($ProcessId, $ProcObj)
    # Primary: WMI CreationDate (most reliable)
    try {
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -Property CreationDate -EA Stop
        if ($ci -and $ci.CreationDate) {
            $cd = $ci.CreationDate
            if ($cd -is [DateTime]) {
                return (Get-Date) - $cd
            }
            # String format: try WMI CIM datetime (yyyyMMddHHmmss...) then formatted
            $s = $cd.ToString()
            try { $ts = [DateTime]::ParseExact($s.Substring(0,14), 'yyyyMMddHHmmss', $null); return (Get-Date) - $ts } catch {}
            try { return (Get-Date) - [DateTime]$s } catch {}
        }
    } catch {}
    # Fallback: Get-Process StartTime
    if ($ProcObj -and $ProcObj.StartTime) {
        try { return (Get-Date) - $ProcObj.StartTime } catch {}
    }
    return $null
}

function Show-Help {
    Write-Host @"
WSL Zombie Killer - Universal Edition

USAGE:
  powershell -File kill-zombie.ps1 -Install       Install
  powershell -File kill-zombie.ps1 -Uninstall     Uninstall
  powershell -File kill-zombie.ps1                Run once

DETECTION (two-phase, no false positives):
   BOOT: kill ALL wslservice + auto-start WSL (once per boot)
   RUNTIME: kill wslservice only if WSL2 NOT running
   WSL alive check: Get-Process vmmem → wsl -l -v → CIM

   Age sources: WMI CreationDate (DateTime/string) → Get-Process StartTime

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
        # If any WSL2 processes exist, kill all + auto-start (once per install)
        if (Test-WSLProcessesExist) {
            Write-Host "WSL2 processes found, cleaning up..."
            Invoke-KillAllWslService
            Write-Host "Resetting WSL..."
            wsl --shutdown 2>$null
            Start-Sleep 10
            Write-Host "Auto-starting WSL..."
            wsl -d $distroName -- uptime 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Host "WSL started." } else { Write-Host "WSL start failed." }
        }
        # Set boot flag BEFORE triggering task, so task instance skips cleanup
        try {
            $bootTime = (Get-CimInstance Win32_OperatingSystem -Property LastBootUpTime -EA Stop).LastBootUpTime
            $bootTime.ToString('o') | Set-Content $bootFlagFile
        } catch {}
        # Kill old zombie killer instances, then trigger fresh
        Get-Process powershell -EA 0 | Where-Object { $_.CommandLine -like "*kill-zombie*" } | Stop-Process -Force -EA 0
        Start-Sleep 2
        schtasks /Run /TN $taskName 2>$null
        Write-Host "Installed and running."
    } else {
        Write-Error "Task creation failed. Run as Administrator."
    }
}

function Uninstall-Tool {
    if (-not (Test-IsAdmin)) { Write-Error "Admin required."; return }
    schtasks /Delete /TN $taskName /F 2>$null
    Write-Host "Uninstalled."
}

# ── Detection ──

function Test-WSLProcessesExist {
    if (Get-Process wslservice -ErrorAction SilentlyContinue) { return $true }
    if (Get-Process vmmem -ErrorAction SilentlyContinue) { return $true }
    if (Get-Process VmmemWSL -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Test-WSLRunning {
    # System-level: is WSL2 VM actually alive?
    if ((Get-Process VmmemWSL -ErrorAction SilentlyContinue) -or (Get-Process vmmem -ErrorAction SilentlyContinue)) {
        return $true
    }
    try {
        $result = wsl -l -v 2>$null | Out-String
        if ($result -match "Running") { return $true }
    } catch {}
    try {
        if (Get-CimInstance Win32_Process -Filter "Name='vmmem.exe' OR Name='VmmemWSL.exe'" -ErrorAction Stop) { return $true }
    } catch {}
    return $false
}

function Test-WSLZombie {
    # Runtime: zombie = WSL2 not running but wslservice still alive
    if (Test-WSLRunning) { return $false }
    return (Get-Process wslservice -ErrorAction SilentlyContinue) -ne $null
}

# ── Kill (multi-method) ──

function Invoke-KillAllWslService {
    Add-Log "Sweeping all wslservice processes..."

    # Phase 1: taskkill by image name (kills ALL wslservice in one shot)
    taskkill /F /IM wslservice.exe 2>$null
    Start-Sleep 2

    # Phase 2: sweep remaining with Stop-Process
    $remaining = @(Get-Process wslservice -ErrorAction SilentlyContinue)
    foreach ($p in $remaining) {
        Stop-Process $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep 2

    # Phase 3: Backstab for any stubborn survivors
    $remaining = @(Get-Process wslservice -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0 -and (Test-Path $backstabPath)) {
        Push-Location $toolsDir
        try {
            for ($i = 0; $i -lt 3; $i++) {
                & $backstabPath -n wslservice.exe -k -d "$toolsDir\" 2>$null
                Start-Sleep 2
                if (-not (Get-Process wslservice -EA 0)) { break }
            }
        } finally { Pop-Location }
    }

    # Phase 4: final taskkill sweep
    taskkill /F /IM wslservice.exe 2>$null
    Start-Sleep 2

    $left = @(Get-Process wslservice -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) {
        Add-Log "All wslservice processes killed"
        return $true
    } else {
        Add-Log "Failed to kill $($left.Count) wslservice process(es) (PID: $($left.Id -join ', '))"
        return $false
    }
}

function Invoke-KillZombie {
    param($Proc)
    $ageStr = ""
    $age = Get-ProcessAge -ProcessId $Proc.Id -ProcObj $Proc
    if ($age) { $ageStr = ", age $([math]::Round($age.TotalMinutes,1)) min" }
    Add-Log "Detected zombie wslservice.exe PID $($Proc.Id)$ageStr"

    # Method 1: Backstab (set working dir so it can write driver)
    if (Test-Path $backstabPath) {
        Push-Location $toolsDir
        try {
            for ($i = 0; $i -lt 3; $i++) {
                & $backstabPath -n wslservice.exe -k -d "$toolsDir\" 2>$null
                Start-Sleep 2
                if (-not (Get-Process wslservice -EA 0)) { break }
            }
        } finally { Pop-Location }
        if (-not (Get-Process wslservice -EA 0)) {
            Add-Log "Killed via Backstab"
            return $true
        }
    }

    # Method 2: taskkill
    taskkill /F /IM wslservice.exe 2>$null; Start-Sleep 1
    if (-not (Get-Process wslservice -EA 0)) {
        Add-Log "Killed via taskkill"
        return $true
    }

    # Method 3: Stop-Process
    $p = Get-Process wslservice -EA 0
    if ($p) { Stop-Process $p.Id -Force -EA 0; Start-Sleep 1 }
    if (-not (Get-Process wslservice -EA 0)) {
        Add-Log "Killed via Stop-Process"
        return $true
    }

    Add-Log "Failed to kill (needs manual)"
    return $false
}

# ── Boot-once cleanup: kill ALL WSL2 processes + auto-start (once per boot) ──

function Invoke-BootCleanup {
    try {
        $bootTime = (Get-CimInstance Win32_OperatingSystem -Property LastBootUpTime -EA Stop).LastBootUpTime
    } catch {
        Add-Log "ERROR: Cannot get boot time: $_"
        return
    }

    if (Test-Path $bootFlagFile) {
        try {
            $stored = (Get-Content $bootFlagFile -Raw).Trim()
            if ($stored -eq $bootTime.ToString('o')) { return }
        } catch {}
    }

    # Kill ALL WSL2 processes if any exist (no zombie/healthy distinction on boot)
    if (Test-WSLProcessesExist) {
        Add-Log "Boot cleanup: WSL2 processes found, killing all..."
        Invoke-KillAllWslService
        Add-Log "Boot cleanup: resetting WSL..."
        wsl --shutdown 2>$null
        Start-Sleep 10
    } else {
        Add-Log "Boot cleanup: no WSL2 processes, skipping"
        # Still need to set flag even if skipped
        try {
            $bootTime = (Get-CimInstance Win32_OperatingSystem -Property LastBootUpTime -EA Stop).LastBootUpTime
            $bootTime.ToString('o') | Set-Content $bootFlagFile
        } catch {}
        return
    }

    Add-Log "Boot cleanup: auto-starting WSL..."
    Start-Sleep 5
    wsl -d $distroName -- uptime 2>$null
    if ($LASTEXITCODE -eq 0) {
        Add-Log "WSL auto-started ($distroName)"
    } else {
        Add-Log "WSL auto-start failed (exit code $LASTEXITCODE)"
    }

    try {
        $bootTime.ToString('o') | Set-Content $bootFlagFile
    } catch {
        Add-Log "ERROR: Cannot write boot flag: $_"
    }
}

# ── Main ──

if ($Help) { Show-Help; return }
if ($Install) { Install-Tool; return }
if ($Uninstall) { Uninstall-Tool; return }

Add-Log "Monitor started (PID $pid)"

while ($true) {
    try {
        # Phase 1: boot cleanup (only once per system boot)
        Invoke-BootCleanup

        # Phase 2: runtime — kill leftover wslservice when WSL2 is not running
        if (Test-WSLZombie) {
            Invoke-KillAllWslService
        }
    } catch {
        Add-Log "ERROR: $_"
    }
    Start-Sleep 60
}
