@echo off
REM Network PC Manager - Shutdown Agent Setup (Python-based)
REM Right-click > "Run as administrator"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_agent.ps1"
pause
