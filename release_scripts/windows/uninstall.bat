@echo off
REM Network PC Manager - Shutdown Agent Uninstaller
REM Right-click > "Run as administrator"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
