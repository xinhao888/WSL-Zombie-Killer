@echo off
cd /d "%~dp0"
title WSL Zombie Killer - Uninstall

schtasks /Query /TN "KillWSLZombie" >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Task "KillWSLZombie" not found. Nothing to uninstall / 未检测到任务，无需卸载.
    pause
    exit /b 1
)

echo [1/2] Removing scheduled task / 删除定时任务...
schtasks /Delete /TN "KillWSLZombie" /F

echo [2/2] Done.
echo.
echo ==============================================
echo   WSL Zombie Killer - Uninstalled! / 已卸载
echo ==============================================
echo.
echo   - Task removed / 任务已删除
echo   - Files NOT deleted / 文件未删除
echo     To fully remove: delete D:\WSL-Tools\ folder
echo     如需彻底移除请手动删除 D:\WSL-Tools\ 文件夹
echo.
echo   To reinstall: run install.bat (Admin)
echo   重新安装: 以管理员运行 install.bat
echo.
pause
