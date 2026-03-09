@echo off
REM ─── Network PC Manager - Shutdown Agent Installer ─────────────────────────
REM Standalone installer - no Python required.
REM ────────────────────────────────────────────────────────────────────────────
setlocal enabledelayedexpansion

echo ======================================================
echo   Network PC Manager - Shutdown Agent Installer
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

REM ─── Verify exe exists next to this script ──────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "EXE_SRC=%SCRIPT_DIR%\shutdown_agent.exe"

if not exist "%EXE_SRC%" (
    echo [ERROR] shutdown_agent.exe not found in %SCRIPT_DIR%
    echo         Make sure install.bat and shutdown_agent.exe are in the same folder.
    echo.
    pause
    exit /b 1
)

REM ─── Prompt for configuration ───────────────────────────────────────────────
echo.
set /p PASSPHRASE="Enter passphrase (min 8 characters): "

if "!PASSPHRASE!"=="" (
    echo [ERROR] Passphrase cannot be empty.
    pause
    exit /b 1
)

set /p PORT="Enter port [9876]: "
if "%PORT%"=="" set PORT=9876

REM ─── Stop any running agent (needed before overwriting the exe) ─────────────
echo [INFO] Stopping any running agent instance...
taskkill /im shutdown_agent.exe /f >nul 2>nul
timeout /t 1 /nobreak >nul 2>nul

REM ─── Install to Program Files ───────────────────────────────────────────────
set "INSTALL_DIR=%ProgramFiles%\NetworkPCManager"

echo.
echo [INFO] Installing to %INSTALL_DIR% ...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /y "%EXE_SRC%" "%INSTALL_DIR%\shutdown_agent.exe" >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy executable. Check permissions.
    pause
    exit /b 1
)
echo [INFO] Executable installed.

REM ─── Set persistent environment variable ────────────────────────────────────
echo [INFO] Storing passphrase in system environment variable...
setx /m NETWORK_PC_MANAGER_AGENT_PASSPHRASE "%PASSPHRASE%" >nul 2>nul
set "NETWORK_PC_MANAGER_AGENT_PASSPHRASE=%PASSPHRASE%"

REM ─── Add Windows Firewall rule ──────────────────────────────────────────────
echo [INFO] Adding firewall rule for port %PORT% ...
netsh advfirewall firewall delete rule name="NetworkPCManager-ShutdownAgent" >nul 2>nul
netsh advfirewall firewall add rule name="NetworkPCManager-ShutdownAgent" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARN] Could not add firewall rule. You may need to allow port %PORT% manually.
) else (
    echo [INFO] Firewall rule added.
)

REM ─── Create Scheduled Task ─────────────────────────────────────────────────
echo [INFO] Creating scheduled task for auto-start at system startup...
set "TASK_NAME=NetworkPCManager-ShutdownAgent"

schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul

schtasks /create /tn "%TASK_NAME%" ^
    /tr "\"%INSTALL_DIR%\shutdown_agent.exe\" --port %PORT%" ^
    /sc onstart /ru SYSTEM /f >nul 2>nul

if %ERRORLEVEL% neq 0 (
    echo [WARN] Could not create scheduled task.
    echo [WARN] You can start the agent manually:
    echo        "%INSTALL_DIR%\shutdown_agent.exe" --passphrase "YOUR_PASSPHRASE" --port %PORT%
) else (
    echo [INFO] Scheduled task "%TASK_NAME%" created (runs at system startup).
)

REM ─── Start the agent now ────────────────────────────────────────────────────
echo [INFO] Starting agent...
start "NetworkPCManager Shutdown Agent" /min "%INSTALL_DIR%\shutdown_agent.exe" --port %PORT%

echo.
echo ======================================================
echo   Installation complete!
echo ======================================================
echo.
echo   Agent installed to: %INSTALL_DIR%
echo   Agent running on port: %PORT%
echo   Starts automatically at system startup (no login required).
echo.
echo   Test with:
echo     curl -s http://localhost:%PORT%/health
echo.
echo   To uninstall, run uninstall.bat as Administrator.
echo.
pause
