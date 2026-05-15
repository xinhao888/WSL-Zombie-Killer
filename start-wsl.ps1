taskkill /f /im wslservice.exe 2>$null
Start-Sleep 5
wsl
Start-Sleep 20

while ($true) {
    if ((Get-Process wslservice -EA 0) -and (-not (Get-Process wslhost -EA 0))) {
        Start-Sleep 4
        if ((-not (Get-Process wslhost -EA 0)) -and (Get-Process wslservice -EA 0)) {
            taskkill /f /im wslservice.exe 2>$null
        }
    }
    Start-Sleep 3
}
