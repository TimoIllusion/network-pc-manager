@echo off
REM ─── WOL-Proxy Shutdown Agent Setup (Windows) ─────────────────────────────
REM Run this on each target Windows machine to install the shutdown agent.
REM Usage: Right-click > Run as Administrator
REM        Or from cmd: setup_agent.bat

setlocal enabledelayedexpansion

echo ======================================================
echo   WOL-Proxy Shutdown Agent Setup (Windows)
echo ======================================================
echo.

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
set "AGENT_SCRIPT=%SCRIPT_DIR%shutdown_agent.py"

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
echo [INFO] Setting WOL_AGENT_PASSPHRASE environment variable...
setx WOL_AGENT_PASSPHRASE "%PASSPHRASE%" >nul 2>nul
set "WOL_AGENT_PASSPHRASE=%PASSPHRASE%"

REM ─── Create a scheduled task to run at startup ─────────────────────────────
echo [INFO] Creating scheduled task for auto-start...

set "TASK_NAME=WOL-Shutdown-Agent"

REM Delete existing task if present
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul

REM Create new task that runs at logon
schtasks /create /tn "%TASK_NAME%" /tr "\"%PYTHON_CMD%\" \"%AGENT_SCRIPT%\" --port %PORT%" /sc onlogon /rl highest /f >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARN] Could not create scheduled task. You may need to run as Administrator.
    echo [WARN] You can start the agent manually:
    echo        %PYTHON_CMD% "%AGENT_SCRIPT%" --passphrase "YOUR_PASSPHRASE" --port %PORT%
) else (
    echo [INFO] Scheduled task "%TASK_NAME%" created successfully.
)

REM ─── Start the agent now ───────────────────────────────────────────────────
echo [INFO] Starting agent...
start "WOL Shutdown Agent" /min %PYTHON_CMD% "%AGENT_SCRIPT%" --port %PORT%

echo.
echo ======================================================
echo   Setup complete!
echo ======================================================
echo.
echo   Agent running on port %PORT%
echo.
echo   Test with:
echo     curl -s http://localhost:%PORT%/health
echo.
echo   Or open in browser: http://localhost:%PORT%/health
echo.
pause
