@echo off
REM Network PC Manager - Shutdown Agent Updater
REM Right-click > "Run as administrator"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
pause
