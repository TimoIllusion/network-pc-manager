# Network PC Manager - Shutdown Agent Setup (Python-based)
# Run as Administrator: Right-click > "Run as administrator"
# Or via setup_agent.bat which handles ExecutionPolicy automatically.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFile = "$env:TEMP\NetworkPCManager_setup.log"
$TaskName = 'NetworkPCManager-ShutdownAgent'
$LegacyTaskName = 'WOL-Shutdown-Agent'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - Shutdown Agent Setup (Windows)'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Shutdown Agent Setup'
Write-Log '======================================================='

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log '[ERROR] Not running as administrator.'
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click setup_agent.bat and select "Run as administrator"'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Find Python ───────────────────────────────────────────────────────────────
$PythonCmd = $null
foreach ($cmd in @('python', 'python3')) {
    try {
        $ver = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $PythonCmd = $cmd
            Write-Log "[INFO] Python found: $cmd -> $ver"
            Write-Host "[INFO] Using: $cmd ($ver)"
            break
        }
    } catch { }
}

if (-not $PythonCmd) {
    Write-Log '[ERROR] Python not found in PATH.'
    Write-Host '[ERROR] Python is not installed or not in PATH.' -ForegroundColor Red
    Write-Host '        Download from https://www.python.org/downloads/'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    exit 1
}

# ── Locate agent script ───────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentScript = Join-Path $ScriptDir 'shutdown_agent.py'
Write-Log "[INFO] Script directory: $ScriptDir"
Write-Log "[INFO] Agent script: $AgentScript"

if (-not (Test-Path $AgentScript)) {
    Write-Log "[ERROR] shutdown_agent.py not found: $AgentScript"
    Write-Host "[ERROR] shutdown_agent.py not found in $ScriptDir" -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    exit 1
}
Write-Log '[INFO] Found shutdown_agent.py - OK'

# ── Prompt ────────────────────────────────────────────────────────────────────
Write-Host ''
$Passphrase = Read-Host 'Enter passphrase (min 8 characters)'
if ($Passphrase.Length -lt 8) {
    Write-Log '[ERROR] Passphrase too short (< 8 characters).'
    Write-Host '[ERROR] Passphrase must be at least 8 characters.' -ForegroundColor Red
    exit 1
}
Write-Log '[INFO] Passphrase provided - OK'

$PortInput = Read-Host 'Enter port [9876]'
$Port = if ($PortInput -match '^\d+$') { [int]$PortInput } else { 9876 }
Write-Log "[INFO] Port: $Port"

# ── Environment variable ──────────────────────────────────────────────────────
Write-Log '[INFO] Setting system environment variable NETWORK_PC_MANAGER_AGENT_PASSPHRASE...'
try {
    [System.Environment]::SetEnvironmentVariable(
        'NETWORK_PC_MANAGER_AGENT_PASSPHRASE', $Passphrase, 'Machine')
    Write-Log '[INFO] Environment variable set - OK'
    Write-Host '[INFO] Passphrase stored in system environment variable.'
} catch {
    Write-Log "[ERROR] Failed to set environment variable: $_"
    Write-Host "[WARN] Could not set environment variable: $_" -ForegroundColor Yellow
}

# ── Scheduled task ────────────────────────────────────────────────────────────
Write-Log '[INFO] Creating scheduled task...'
try {
    # Remove legacy task
    Unregister-ScheduledTask -TaskName $LegacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
    # Remove existing task
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log '[INFO] Old tasks removed (if any).'

    $PythonFull = (Get-Command $PythonCmd -ErrorAction Stop).Source
    Write-Log "[INFO] Python full path: $PythonFull"

    $action    = New-ScheduledTaskAction -Execute $PythonFull -Argument "`"$AgentScript`" --port $Port"
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

    Write-Log "[INFO] Scheduled task '$TaskName' created - OK"
    Write-Host "[INFO] Scheduled task '$TaskName' created (runs at system startup)."
} catch {
    Write-Log "[WARN] Could not create scheduled task: $_"
    Write-Host "[WARN] Could not create scheduled task: $_" -ForegroundColor Yellow
    Write-Host '[WARN] You can start the agent manually:'
    Write-Host "       $PythonCmd `"$AgentScript`" --port $Port"
}

# ── Start agent now ───────────────────────────────────────────────────────────
Write-Log '[INFO] Starting agent...'
try {
    Start-Process -FilePath $PythonCmd -ArgumentList "`"$AgentScript`" --port $Port --passphrase `"$Passphrase`"" -WindowStyle Minimized
    Write-Log '[INFO] Agent started.'
    Write-Host '[INFO] Agent started.'
} catch {
    Write-Log "[WARN] Could not start agent: $_"
    Write-Host "[WARN] Could not start agent: $_" -ForegroundColor Yellow
}

Write-Log '[INFO] Setup complete.'
Write-Host ''
Write-Host '======================================================='
Write-Host '  Setup complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Agent running on port : $Port"
Write-Host '  Auto-starts at system startup (no login required).'
Write-Host ''
Write-Host "  Test: http://localhost:$Port/health"
Write-Host ''
Write-Host "  Setup log : $LogFile"
Write-Host "  Agent log : $env:ProgramData\NetworkPCManager\shutdown_agent.log"
Write-Host ''
