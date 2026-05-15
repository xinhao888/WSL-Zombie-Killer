@echo off
cd /d "%~dp0"
powershell -File "%~dp0kill-zombie.ps1" -Install
pause
