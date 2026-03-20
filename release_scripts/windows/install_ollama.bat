@echo off
:: Thin launcher for install_ollama.ps1 — requests elevation automatically.
:: Just double-click this file or run from an admin command prompt.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ollama.ps1"
echo.
pause
