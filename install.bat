@echo off
cd /d "%~dp0"
title WSL Zombie Killer - Install / 安装

schtasks /Query /TN "KillWSLZombie" >nul 2>&1
if %errorlevel% equ 0 (
    echo [INFO] Task "KillWSLZombie" already exists. Uninstall first / 任务已存在，请先卸载.
    pause
    exit /b 1
)

echo [1/5] Adding Defender exclusion / 添加排除项...
powershell -Command "Add-MpPreference -ExclusionPath '%~dp0' -ErrorAction SilentlyContinue" >nul 2>&1

echo [2/5] Checking Backstab...
if not exist "%~dp0Backstab64.exe" (
    echo   Downloading from GitHub...
    curl.exe -L -o "%~dp0Backstab64.exe" "https://github.com/Yaxser/Backstab/releases/download/v1.0.1-beta/Backstab64.exe" --connect-timeout 30 --max-time 120 >nul 2>&1
    if not exist "%~dp0Backstab64.exe" (
        echo   [WARNING] Download failed. Get it manually / 下载失败，手动下载:
        echo   https://github.com/Yaxser/Backstab/releases/download/v1.0.1-beta/Backstab64.exe
        echo   Save to / 保存到: %~dp0Backstab64.exe
    ) else (
        echo   Done / 完成.
    )
) else (
    echo   Already present / 已存在.
)

echo [3/5] Generating task config for this path...
powershell -Command "$raw='%~dp0kill-zombie.ps1'; (Get-Content '%~dp0zombie-killer-task.xml' -Raw) -replace 'D:\\WSL-Tools\\kill-zombie\.ps1', $raw | Set-Content '%~dp0zombie-killer-task-temp.xml' -Encoding Unicode"

echo [4/5] Registering scheduled task / 注册定时任务...
schtasks /Create /TN "KillWSLZombie" /XML "%~dp0zombie-killer-task-temp.xml" /F
if %errorlevel% neq 0 (
    echo [ERROR] Task creation failed. Run as Administrator / 失败，请以管理员运行.
    del "%~dp0zombie-killer-task-temp.xml" >nul 2>&1
    pause
    exit /b 1
)
del "%~dp0zombie-killer-task-temp.xml" >nul 2>&1

echo [5/5] Done / 完成.
echo.
echo ==============================================
echo   WSL Zombie Killer - Universal Edition
echo   Installed! / 安装完成！
echo ==============================================
echo.
echo   Triggers / 触发: boot + WSL restart
echo   Check every / 检测频率: 30 seconds
echo   Kill methods / 杀法: Backstab ^> taskkill ^> Stop-Process
echo   Log / 日志: %~dp0zombie-kill.log
echo   Uninstall / 卸载: uninstall.bat (Admin)
echo.
echo   GitHub: https://github.com/xinhao888/WSL-Zombie-Killer
echo.
pause
