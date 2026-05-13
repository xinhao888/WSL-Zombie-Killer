@echo off
cd /d "%~dp0"
title 卸载 - 自动杀WSL僵尸进程

schtasks /Query /TN "KillWSLZombie" >nul 2>&1
if %errorlevel% neq 0 (
    echo [!!!] 未检测到 KillWSLZombie 任务，无需卸载。
    pause
    exit /b 1
)

echo [1/2] 删除定时任务...
schtasks /Delete /TN "KillWSLZombie" /F

echo [2/2] 清理排除项（如有需要可手动操作，不影响系统）
echo.
echo ============================================
echo   卸载完成!
echo ============================================
echo.
echo   文件未删除，如需彻底移除请手动删除:
echo     D:\WSL-Tools\ 整个文件夹
echo.
echo   如需重新安装，直接运行 install.bat 即可。
echo.
pause
