# Network PC Manager - Shutdown Agent Installer
# Run as Administrator: Right-click > "Run as administrator"
# Or via install.bat which handles ExecutionPolicy automatically.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $ScriptDir 'install.log'
$TaskName = 'NetworkPCManager-ShutdownAgent'
$InstallDir = "$env:ProgramFiles\NetworkPCManager"
$FirewallRuleName = 'NetworkPCManager-ShutdownAgent'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - Shutdown Agent Installer'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Shutdown Agent Installer'
Write-Log '======================================================='

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log '[ERROR] Not running as administrator.'
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click install.bat and select "Run as administrator"'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Locate exe ────────────────────────────────────────────────────────────────
$ExeSrc = Join-Path $ScriptDir 'shutdown_agent.exe'
Write-Log "[INFO] Script directory: $ScriptDir"
Write-Log "[INFO] Looking for: $ExeSrc"

if (-not (Test-Path $ExeSrc)) {
    Write-Log "[ERROR] shutdown_agent.exe not found: $ExeSrc"
    Write-Host "[ERROR] shutdown_agent.exe not found in $ScriptDir" -ForegroundColor Red
    Write-Host '        Make sure install.bat and shutdown_agent.exe are in the same folder.'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    exit 1
}
Write-Log '[INFO] Found shutdown_agent.exe - OK'

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

# ── Stop running agent ────────────────────────────────────────────────────────
Write-Log '[INFO] Stopping any running agent instance...'
Stop-Process -Name 'shutdown_agent' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ── Install exe ───────────────────────────────────────────────────────────────
Write-Log "[INFO] Installing to: $InstallDir"
try {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path $ExeSrc -Destination "$InstallDir\shutdown_agent.exe" -Force
    Write-Log '[INFO] Executable copied successfully.'
    Write-Host '[INFO] Executable installed.'
} catch {
    Write-Log "[ERROR] Failed to copy executable: $_"
    Write-Host "[ERROR] Failed to copy executable: $_" -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    exit 1
}

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

# ── Firewall rule ─────────────────────────────────────────────────────────────
Write-Log "[INFO] Adding firewall rule for port $Port..."
try {
    Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $FirewallRuleName `
        -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    Write-Log '[INFO] Firewall rule added - OK'
    Write-Host '[INFO] Firewall rule added.'
} catch {
    Write-Log "[WARN] Could not add firewall rule: $_"
    Write-Host "[WARN] Could not add firewall rule. You may need to allow port $Port manually." -ForegroundColor Yellow
}

# ── Scheduled task ────────────────────────────────────────────────────────────
Write-Log '[INFO] Creating scheduled task...'
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action   = New-ScheduledTaskAction -Execute "$InstallDir\shutdown_agent.exe" -Argument "--port $Port"
    $trigger  = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

    Write-Log "[INFO] Scheduled task '$TaskName' created - OK"
    Write-Host "[INFO] Scheduled task '$TaskName' created (runs at system startup)."
} catch {
    Write-Log "[WARN] Could not create scheduled task: $_"
    Write-Host "[WARN] Could not create scheduled task: $_" -ForegroundColor Yellow
    Write-Host "[WARN] You can start the agent manually:"
    Write-Host "       `"$InstallDir\shutdown_agent.exe`" --port $Port"
}

# ── Start agent now ───────────────────────────────────────────────────────────
Write-Log '[INFO] Starting agent...'
try {
    Start-Process -FilePath "$InstallDir\shutdown_agent.exe" -ArgumentList "--port $Port --passphrase `"$Passphrase`"" -WindowStyle Minimized
    Write-Log '[INFO] Agent started.'
    Write-Host '[INFO] Agent started.'
} catch {
    Write-Log "[WARN] Could not start agent: $_"
    Write-Host "[WARN] Could not start agent: $_" -ForegroundColor Yellow
}

Write-Log '[INFO] Installation complete.'
Write-Host ''
Write-Host '======================================================='
Write-Host '  Installation complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Agent installed to : $InstallDir"
Write-Host "  Port               : $Port"
Write-Host '  Auto-starts at system startup (no login required).'
Write-Host ''
Write-Host "  Test: http://localhost:$Port/health"
Write-Host ''
Write-Host '  To uninstall, run uninstall.bat as Administrator.'
Write-Host ''
Write-Host "  Install log: $LogFile"
Write-Host "  Agent log  : $env:ProgramData\NetworkPCManager\shutdown_agent.log"
Write-Host ''
