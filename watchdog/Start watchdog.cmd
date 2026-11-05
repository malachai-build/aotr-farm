@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0aotr_watchdog_portable.ps1" -RestartMatcha -RestartOnTeleport
pause
