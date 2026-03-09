# Network PC Manager - Shutdown Agent Uninstaller
# Run as Administrator: Right-click > "Run as administrator"
# Or via uninstall.bat which handles ExecutionPolicy automatically.

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

$LogFile = "$env:TEMP\NetworkPCManager_uninstall.log"
$InstallDir = "$env:ProgramFiles\NetworkPCManager"
$TaskName = 'NetworkPCManager-ShutdownAgent'
$LegacyTaskName = 'WOL-Shutdown-Agent'
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
Write-Host '  Network PC Manager - Shutdown Agent Uninstaller'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Shutdown Agent Uninstaller'
Write-Log '======================================================='

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log '[ERROR] Not running as administrator.'
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click uninstall.bat and select "Run as administrator"'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Stop running agent ────────────────────────────────────────────────────────
Write-Log '[INFO] Stopping running agent...'
Stop-Process -Name 'shutdown_agent' -Force -ErrorAction SilentlyContinue
Write-Log '[INFO] Stop-Process done (no error if process was not running).'

# ── Remove scheduled tasks ────────────────────────────────────────────────────
Write-Log "[INFO] Removing scheduled task '$TaskName'..."
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Log "[INFO] Removing legacy scheduled task '$LegacyTaskName'..."
Unregister-ScheduledTask -TaskName $LegacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host '[INFO] Scheduled tasks removed.'

# ── Remove firewall rule ──────────────────────────────────────────────────────
Write-Log "[INFO] Removing firewall rule '$FirewallRuleName'..."
Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
Write-Host '[INFO] Firewall rule removed.'

# ── Remove environment variables ──────────────────────────────────────────────
Write-Log '[INFO] Removing environment variables...'
[System.Environment]::SetEnvironmentVariable('NETWORK_PC_MANAGER_AGENT_PASSPHRASE', $null, 'Machine')
[System.Environment]::SetEnvironmentVariable('WOL_AGENT_PASSPHRASE', $null, 'Machine')
Write-Log '[INFO] Environment variables removed.'
Write-Host '[INFO] Environment variables removed.'

# ── Remove installed files ────────────────────────────────────────────────────
Write-Log "[INFO] Removing install directory: $InstallDir"
if (Test-Path $InstallDir) {
    try {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Log '[INFO] Install directory removed - OK'
        Write-Host '[INFO] Installed files removed.'
    } catch {
        Write-Log "[WARN] Could not fully remove install directory: $_"
        Write-Host "[WARN] Could not fully remove install directory: $_" -ForegroundColor Yellow
    }
} else {
    Write-Log '[INFO] Install directory not found - nothing to remove.'
    Write-Host '[INFO] Install directory not found (already removed or never installed).'
}

Write-Log '[INFO] Uninstall complete.'
Write-Host ''
Write-Host '======================================================='
Write-Host '  Uninstall complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host '  The shutdown agent has been fully removed.'
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''
