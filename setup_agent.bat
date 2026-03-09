@echo off
REM ─── Network PC Manager - Shutdown Agent Setup (Windows) ──────────────────
REM Run this on each target Windows machine to install the shutdown agent.
REM Usage: Right-click > Run as Administrator
REM        Or from cmd: setup_agent.bat

setlocal enabledelayedexpansion

echo ======================================================
echo   Network PC Manager - Shutdown Agent Setup (Windows)
echo ======================================================
echo.

REM ─── Auto-elevate if not running as admin ──────────────────────────────────
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting administrator privileges...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%TEMP%\npm_elevate.vbs"
    echo UAC.ShellExecute "%~f0", "", "%~dp0", "runas", 1 >> "%TEMP%\npm_elevate.vbs"
    cscript //nologo "%TEMP%\npm_elevate.vbs"
    del "%TEMP%\npm_elevate.vbs" >nul 2>nul
    exit /b
)

REM ─── Ensure working directory is the script's directory ────────────────────
pushd "%~dp0" || (
    echo [ERROR] Cannot access script directory: %~dp0
    pause
    exit /b 1
)

REM ─── Check Python ──────────────────────────────────────────────────────────
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where python3 >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Python is not installed or not in PATH.
        echo         Download from https://www.python.org/downloads/
        pause
        exit /b 1
    )
    set PYTHON_CMD=python3
) else (
    set PYTHON_CMD=python
)

echo [INFO] Using: %PYTHON_CMD%

REM ─── Get script directory ──────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "AGENT_SCRIPT=%SCRIPT_DIR%\shutdown_agent.py"

if not exist "%AGENT_SCRIPT%" (
    echo [ERROR] shutdown_agent.py not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

REM ─── Prompt for configuration ──────────────────────────────────────────────
echo.
set /p PASSPHRASE="Enter passphrase (min 8 characters): "
set /p PORT="Enter port [9876]: "
if "%PORT%"=="" set PORT=9876

REM ─── Set persistent environment variable ───────────────────────────────────
echo [INFO] Setting NETWORK_PC_MANAGER_AGENT_PASSPHRASE environment variable...
setx /m NETWORK_PC_MANAGER_AGENT_PASSPHRASE "%PASSPHRASE%" >nul 2>nul
set "NETWORK_PC_MANAGER_AGENT_PASSPHRASE=%PASSPHRASE%"

REM ─── Create a scheduled task to run at system startup ──────────────────────
echo [INFO] Creating scheduled task for auto-start at system startup...

set "TASK_NAME=NetworkPCManager-ShutdownAgent"

REM Remove legacy task name if present (from older versions)
schtasks /delete /tn "WOL-Shutdown-Agent" /f >nul 2>nul

REM Delete existing task if present
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul

REM Create new task that runs at system startup (no login required)
schtasks /create /tn "%TASK_NAME%" /tr "\"%PYTHON_CMD%\" \"%AGENT_SCRIPT%\" --port %PORT%" /sc onstart /ru SYSTEM /f >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARN] Could not create scheduled task. You may need to run as Administrator.
    echo [WARN] You can start the agent manually:
    echo        %PYTHON_CMD% "%AGENT_SCRIPT%" --passphrase "YOUR_PASSPHRASE" --port %PORT%
) else (
    echo [INFO] Scheduled task "%TASK_NAME%" created (runs at system startup).
)

REM ─── Start the agent now ───────────────────────────────────────────────────
echo [INFO] Starting agent...
start "NetworkPCManager Shutdown Agent" /min %PYTHON_CMD% "%AGENT_SCRIPT%" --port %PORT%

echo.
echo ======================================================
echo   Setup complete!
echo ======================================================
echo.
echo   Agent running on port %PORT%
echo   Starts automatically at system startup (no login required).
echo.
echo   Test with:
echo     curl -s http://localhost:%PORT%/health
echo.
echo   Or open in browser: http://localhost:%PORT%/health
echo.
pause
