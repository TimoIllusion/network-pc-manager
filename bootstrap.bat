@echo off
REM Network PC Manager - Full PC Bootstrap
REM Right-click > "Run as administrator"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
pause
