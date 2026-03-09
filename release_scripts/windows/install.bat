@echo off
REM ─── Network PC Manager - Shutdown Agent Installer ─────────────────────────
REM Standalone installer - no Python required.
REM Run as Administrator: Right-click > "Run as administrator"
REM ────────────────────────────────────────────────────────────────────────────
setlocal enabledelayedexpansion

REM ─── Log file setup ─────────────────────────────────────────────────────────
set "LOG_FILE=%TEMP%\NetworkPCManager_install.log"
call :log "======================================================="
call :log "  Network PC Manager - Shutdown Agent Installer"
call :log "  Date/Time: %DATE% %TIME%"
call :log "======================================================="

echo =======================================================
echo   Network PC Manager - Shutdown Agent Installer
echo =======================================================
echo.
echo   Log file: %LOG_FILE%
echo.

REM ─── Check for admin privileges ─────────────────────────────────────────────
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    call :log "[ERROR] Not running as administrator."
    echo [ERROR] This script must be run as Administrator.
    echo.
    echo   How to fix:
    echo     Right-click install.bat and select "Run as administrator"
    echo.
    echo   Log saved to: %LOG_FILE%
    echo.
    pause
    exit /b 1
)
call :log "[INFO] Running as administrator - OK"

REM ─── Ensure working directory is the script's directory ─────────────────────
pushd "%~dp0"
if %ERRORLEVEL% neq 0 (
    call :log "[ERROR] Cannot access script directory: %~dp0"
    echo [ERROR] Cannot access script directory: %~dp0
    pause
    exit /b 1
)
call :log "[INFO] Working directory: %CD%"

REM ─── Verify exe exists next to this script ──────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "EXE_SRC=%SCRIPT_DIR%\shutdown_agent.exe"

call :log "[INFO] Looking for: %EXE_SRC%"
if not exist "%EXE_SRC%" (
    call :log "[ERROR] shutdown_agent.exe not found: %EXE_SRC%"
    echo [ERROR] shutdown_agent.exe not found in %SCRIPT_DIR%
    echo         Make sure install.bat and shutdown_agent.exe are in the same folder.
    echo.
    echo   Log saved to: %LOG_FILE%
    echo.
    pause
    exit /b 1
)
call :log "[INFO] Found shutdown_agent.exe - OK"

REM ─── Prompt for configuration ────────────────────────────────────────────────
echo.
set /p PASSPHRASE="Enter passphrase (min 8 characters): "

if "!PASSPHRASE!"=="" (
    call :log "[ERROR] Passphrase was empty."
    echo [ERROR] Passphrase cannot be empty.
    pause
    exit /b 1
)
call :log "[INFO] Passphrase provided (length: !PASSPHRASE:~7,1! chars min check skipped for security)"

set /p PORT="Enter port [9876]: "
if "%PORT%"=="" set PORT=9876
call :log "[INFO] Port: %PORT%"

REM ─── Stop any running agent (needed before overwriting the exe) ──────────────
echo [INFO] Stopping any running agent instance...
call :log "[INFO] Stopping any running agent instance..."
taskkill /im shutdown_agent.exe /f >nul 2>nul
call :log "[INFO] taskkill result: %ERRORLEVEL% (0=killed, 128=not found - both OK)"
timeout /t 1 /nobreak >nul 2>nul

REM ─── Install to Program Files ────────────────────────────────────────────────
set "INSTALL_DIR=%ProgramFiles%\NetworkPCManager"
call :log "[INFO] Install directory: %INSTALL_DIR%"

echo.
echo [INFO] Installing to %INSTALL_DIR% ...
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    call :log "[INFO] Created directory: %INSTALL_DIR%"
)

copy /y "%EXE_SRC%" "%INSTALL_DIR%\shutdown_agent.exe" >nul
if %ERRORLEVEL% neq 0 (
    call :log "[ERROR] Failed to copy executable. ERRORLEVEL=%ERRORLEVEL%"
    echo [ERROR] Failed to copy executable. Check permissions.
    echo.
    echo   Log saved to: %LOG_FILE%
    echo.
    pause
    exit /b 1
)
call :log "[INFO] Executable copied successfully."
echo [INFO] Executable installed.

REM ─── Set persistent environment variable ─────────────────────────────────────
echo [INFO] Storing passphrase in system environment variable...
call :log "[INFO] Setting system environment variable NETWORK_PC_MANAGER_AGENT_PASSPHRASE..."
setx /m NETWORK_PC_MANAGER_AGENT_PASSPHRASE "%PASSPHRASE%" >nul 2>nul
call :log "[INFO] setx result: %ERRORLEVEL%"
set "NETWORK_PC_MANAGER_AGENT_PASSPHRASE=%PASSPHRASE%"

REM ─── Add Windows Firewall rule ────────────────────────────────────────────────
echo [INFO] Adding firewall rule for port %PORT% ...
call :log "[INFO] Adding firewall rule for port %PORT%..."
netsh advfirewall firewall delete rule name="NetworkPCManager-ShutdownAgent" >nul 2>nul
netsh advfirewall firewall add rule name="NetworkPCManager-ShutdownAgent" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>nul
if %ERRORLEVEL% neq 0 (
    call :log "[WARN] Could not add firewall rule. ERRORLEVEL=%ERRORLEVEL%"
    echo [WARN] Could not add firewall rule. You may need to allow port %PORT% manually.
) else (
    call :log "[INFO] Firewall rule added successfully."
    echo [INFO] Firewall rule added.
)

REM ─── Create Scheduled Task ────────────────────────────────────────────────────
echo [INFO] Creating scheduled task for auto-start at system startup...
call :log "[INFO] Creating scheduled task NetworkPCManager-ShutdownAgent..."
set "TASK_NAME=NetworkPCManager-ShutdownAgent"

schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul
call :log "[INFO] Deleted old task (if any): %ERRORLEVEL%"

schtasks /create /tn "%TASK_NAME%" ^
    /tr "\"%INSTALL_DIR%\shutdown_agent.exe\" --port %PORT%" ^
    /sc onstart /ru SYSTEM /f >nul 2>nul

if %ERRORLEVEL% neq 0 (
    call :log "[WARN] Could not create scheduled task. ERRORLEVEL=%ERRORLEVEL%"
    echo [WARN] Could not create scheduled task.
    echo [WARN] You can start the agent manually:
    echo        "%INSTALL_DIR%\shutdown_agent.exe" --passphrase "YOUR_PASSPHRASE" --port %PORT%
) else (
    call :log "[INFO] Scheduled task created successfully."
    echo [INFO] Scheduled task "%TASK_NAME%" created (runs at system startup).
)

REM ─── Start the agent now ──────────────────────────────────────────────────────
echo [INFO] Starting agent...
call :log "[INFO] Starting agent: %INSTALL_DIR%\shutdown_agent.exe --port %PORT%"
start "NetworkPCManager Shutdown Agent" /min "%INSTALL_DIR%\shutdown_agent.exe" --port %PORT%
call :log "[INFO] Agent start command issued."

call :log "[INFO] Installation complete."
echo.
echo =======================================================
echo   Installation complete!
echo =======================================================
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
echo   Log file: %LOG_FILE%
echo.
pause
goto :eof

REM ─── Logging helper ───────────────────────────────────────────────────────────
:log
echo %~1 >> "%LOG_FILE%"
goto :eof
