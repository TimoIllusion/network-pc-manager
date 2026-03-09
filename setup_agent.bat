@echo off
REM ─── Network PC Manager - Shutdown Agent Setup (Windows) ──────────────────
REM Run this on each target Windows machine to install the shutdown agent.
REM Run as Administrator: Right-click > "Run as administrator"
REM ────────────────────────────────────────────────────────────────────────────
setlocal enabledelayedexpansion

REM ─── Log file setup ─────────────────────────────────────────────────────────
set "LOG_FILE=%TEMP%\NetworkPCManager_setup.log"
call :log "======================================================="
call :log "  Network PC Manager - Shutdown Agent Setup"
call :log "  Date/Time: %DATE% %TIME%"
call :log "======================================================="

echo =======================================================
echo   Network PC Manager - Shutdown Agent Setup (Windows)
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
    echo     Right-click setup_agent.bat and select "Run as administrator"
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

REM ─── Check Python ────────────────────────────────────────────────────────────
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where python3 >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        call :log "[ERROR] Python not found in PATH."
        echo [ERROR] Python is not installed or not in PATH.
        echo         Download from https://www.python.org/downloads/
        echo.
        echo   Log saved to: %LOG_FILE%
        echo.
        pause
        exit /b 1
    )
    set PYTHON_CMD=python3
) else (
    set PYTHON_CMD=python
)
call :log "[INFO] Python command: %PYTHON_CMD%"

for /f "tokens=*" %%V in ('%PYTHON_CMD% --version 2^>^&1') do (
    call :log "[INFO] Python version: %%V"
)
echo [INFO] Using: %PYTHON_CMD%

REM ─── Get script directory ────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "AGENT_SCRIPT=%SCRIPT_DIR%\shutdown_agent.py"

call :log "[INFO] Agent script path: %AGENT_SCRIPT%"
if not exist "%AGENT_SCRIPT%" (
    call :log "[ERROR] shutdown_agent.py not found: %AGENT_SCRIPT%"
    echo [ERROR] shutdown_agent.py not found in %SCRIPT_DIR%
    echo.
    echo   Log saved to: %LOG_FILE%
    echo.
    pause
    exit /b 1
)
call :log "[INFO] Found shutdown_agent.py - OK"

REM ─── Prompt for configuration ────────────────────────────────────────────────
echo.
set /p PASSPHRASE="Enter passphrase (min 8 characters): "
set /p PORT="Enter port [9876]: "
if "%PORT%"=="" set PORT=9876
call :log "[INFO] Port: %PORT%"

REM ─── Set persistent environment variable ─────────────────────────────────────
echo [INFO] Setting NETWORK_PC_MANAGER_AGENT_PASSPHRASE environment variable...
call :log "[INFO] Setting system environment variable NETWORK_PC_MANAGER_AGENT_PASSPHRASE..."
setx /m NETWORK_PC_MANAGER_AGENT_PASSPHRASE "%PASSPHRASE%" >nul 2>nul
call :log "[INFO] setx result: %ERRORLEVEL%"
set "NETWORK_PC_MANAGER_AGENT_PASSPHRASE=%PASSPHRASE%"

REM ─── Create a scheduled task to run at system startup ────────────────────────
echo [INFO] Creating scheduled task for auto-start at system startup...
call :log "[INFO] Creating scheduled task..."
set "TASK_NAME=NetworkPCManager-ShutdownAgent"

REM Remove legacy task name if present (from older versions)
schtasks /delete /tn "WOL-Shutdown-Agent" /f >nul 2>nul

REM Delete existing task if present
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul
call :log "[INFO] Deleted old task (if any)."

REM Create new task that runs at system startup (no login required)
schtasks /create /tn "%TASK_NAME%" /tr "\"%PYTHON_CMD%\" \"%AGENT_SCRIPT%\" --port %PORT%" /sc onstart /ru SYSTEM /f >nul 2>nul
if %ERRORLEVEL% neq 0 (
    call :log "[WARN] Could not create scheduled task. ERRORLEVEL=%ERRORLEVEL%"
    echo [WARN] Could not create scheduled task. You may need to run as Administrator.
    echo [WARN] You can start the agent manually:
    echo        %PYTHON_CMD% "%AGENT_SCRIPT%" --passphrase "YOUR_PASSPHRASE" --port %PORT%
) else (
    call :log "[INFO] Scheduled task created successfully."
    echo [INFO] Scheduled task "%TASK_NAME%" created (runs at system startup).
)

REM ─── Start the agent now ──────────────────────────────────────────────────────
echo [INFO] Starting agent...
call :log "[INFO] Starting agent: %PYTHON_CMD% %AGENT_SCRIPT% --port %PORT%"
start "NetworkPCManager Shutdown Agent" /min %PYTHON_CMD% "%AGENT_SCRIPT%" --port %PORT%
call :log "[INFO] Agent start command issued."

call :log "[INFO] Setup complete."
echo.
echo =======================================================
echo   Setup complete!
echo =======================================================
echo.
echo   Agent running on port %PORT%
echo   Starts automatically at system startup (no login required).
echo.
echo   Test with:
echo     curl -s http://localhost:%PORT%/health
echo.
echo   Or open in browser: http://localhost:%PORT%/health
echo.
echo   Log file: %LOG_FILE%
echo.
pause
goto :eof

REM ─── Logging helper ───────────────────────────────────────────────────────────
:log
echo %~1 >> "%LOG_FILE%"
goto :eof
