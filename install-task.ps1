param(
    [switch]$Uninstall
)

$taskName = "StartWSL"
$scriptDir = $PSScriptRoot
$startScript = Join-Path $scriptDir "start-wsl.ps1"

if ($Uninstall) {
    schtasks /Delete /TN $taskName /F 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Task '$taskName' uninstalled successfully."
    } else {
        Write-Host "Task '$taskName' not found or already removed."
    }
    exit 0
}

if (-not (Test-Path $startScript)) {
    Write-Host "ERROR: start-wsl.ps1 not found at $startScript"
    exit 1
}

# Remove old task if exists
schtasks /Delete /TN $taskName /F 2>$null

# Create task
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT10S"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force

Write-Host "Task '$taskName' installed successfully."
Write-Host "  Script : $startScript"
Write-Host "  User   : $env:USERDOMAIN\$env:USERNAME"
