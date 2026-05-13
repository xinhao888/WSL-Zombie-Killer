@echo off
cd /d "%~dp0"
title WSL Zombie Killer - Install

schtasks /Query /TN "KillWSLZombie" >nul 2>&1
if %errorlevel% equ 0 (
    echo [INFO] Task "KillWSLZombie" already exists.
    echo        Run uninstall.bat first if you want to reinstall.
    pause
    exit /b 1
)

echo [1/4] Adding Defender exclusion...
powershell -Command "Add-MpPreference -ExclusionPath '%~dp0' -ErrorAction SilentlyContinue" >nul 2>&1

echo [2/4] Checking Backstab...
if not exist "%~dp0Backstab64.exe" (
    echo   Downloading from GitHub...
    curl.exe -L -o "%~dp0Backstab64.exe" "https://github.com/Yaxser/Backstab/releases/download/Beta/Backstab64.exe" --connect-timeout 30 --max-time 120 >nul 2>&1
    if not exist "%~dp0Backstab64.exe" (
        echo   [WARNING] Download failed. Get it manually:
        echo   https://github.com/Yaxser/Backstab/releases/download/Beta/Backstab64.exe
        echo   Save to: %~dp0Backstab64.exe
    ) else (
        echo   Done.
    )
) else (
    echo   Already present.
)

echo [3/4] Registering scheduled task...
schtasks /Create /TN "KillWSLZombie" /XML "%~dp0zombie-killer-task.xml" /F
if %errorlevel% neq 0 (
    echo [ERROR] Task creation failed. Run as Administrator.
    pause
    exit /b 1
)

echo [4/4] Done.
echo.
echo ==============================================
echo   WSL Zombie Killer - Universal Edition
echo   Installed successfully!
echo ==============================================
echo.
echo   Triggers:
echo     - Windows boot
echo     - WSL (LxssManager) restart
echo.
echo   Detection: every 30 seconds
echo   Kill: Backstab ^> taskkill ^> Stop-Process
echo.
echo   Log: %~dp0zombie-kill.log
echo.
echo   Uninstall: run uninstall.bat (Admin)
echo.
pause
