@echo off
REM Network PC Manager - Shutdown Agent Installer
REM Right-click > "Run as administrator"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause
