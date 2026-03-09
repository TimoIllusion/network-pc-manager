@echo off
REM ─── Network PC Manager - Shutdown Agent Uninstaller ───────────────────────
REM ────────────────────────────────────────────────────────────────────────────
setlocal

echo ======================================================
echo   Network PC Manager - Shutdown Agent Uninstaller
echo ======================================================
echo.

REM ─── Auto-elevate if not running as admin ───────────────────────────────────
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0.'"
    exit /b
)
cd /d "%~dp0"

set "INSTALL_DIR=%ProgramFiles%\NetworkPCManager"
set "TASK_NAME=NetworkPCManager-ShutdownAgent"

REM ─── Stop running agent ─────────────────────────────────────────────────────
echo [INFO] Stopping running agent...
taskkill /im shutdown_agent.exe /f >nul 2>nul

REM ─── Remove scheduled task (current and legacy names) ──────────────────────
echo [INFO] Removing scheduled task...
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul
schtasks /delete /tn "WOL-Shutdown-Agent" /f >nul 2>nul

REM ─── Remove firewall rule ───────────────────────────────────────────────────
echo [INFO] Removing firewall rule...
netsh advfirewall firewall delete rule name="NetworkPCManager-ShutdownAgent" >nul 2>nul

REM ─── Remove environment variables (current and legacy names) ────────────────
echo [INFO] Removing environment variables...
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v NETWORK_PC_MANAGER_AGENT_PASSPHRASE /f >nul 2>nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v WOL_AGENT_PASSPHRASE /f >nul 2>nul

REM ─── Remove installed files ─────────────────────────────────────────────────
echo [INFO] Removing installed files...
if exist "%INSTALL_DIR%" (
    rmdir /s /q "%INSTALL_DIR%"
)

echo.
echo ======================================================
echo   Uninstall complete!
echo ======================================================
echo.
echo   The shutdown agent has been fully removed.
echo.
pause
