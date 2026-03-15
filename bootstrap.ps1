# Network PC Manager - Full PC Bootstrap Setup
# =============================================
# Run as Administrator: Right-click > "Run as administrator"
# Or via bootstrap.bat which handles ExecutionPolicy automatically.
#
# This script performs a complete setup of a new Windows PC:
#   1. Enables OpenSSH Server (for remote management)
#   2. Installs the Shutdown Agent (for network-pc-manager integration)
#   3. Installs software packages via winget (configurable list)

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFile = "$env:TEMP\NetworkPCManager_bootstrap.log"
$TaskName = 'NetworkPCManager-ShutdownAgent'
$LegacyTaskName = 'WOL-Shutdown-Agent'
$DefaultAgentPort = 9876
$DefaultSSHPort = 22

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Write-Step {
    param([string]$Step, [string]$Desc)
    Write-Host ''
    Write-Host "  [$Step] $Desc" -ForegroundColor Cyan
    Write-Host "  $('-' * (4 + $Step.Length + $Desc.Length))" -ForegroundColor DarkGray
    Write-Log "=== STEP $Step : $Desc ==="
}

function Write-OK {
    param([string]$Msg)
    Write-Host "       OK: $Msg" -ForegroundColor Green
    Write-Log "[OK] $Msg"
}

function Write-Warn {
    param([string]$Msg)
    Write-Host "     WARN: $Msg" -ForegroundColor Yellow
    Write-Log "[WARN] $Msg"
}

function Write-Err {
    param([string]$Msg)
    Write-Host "    ERROR: $Msg" -ForegroundColor Red
    Write-Log "[ERROR] $Msg"
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - Full PC Bootstrap'
Write-Host '======================================================='
Write-Host ''
Write-Host "  This script will set up:"
Write-Host "    1. OpenSSH Server (remote access)"
Write-Host "    2. Shutdown Agent (network-pc-manager integration)"
Write-Host "    3. Software packages via winget"
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Full PC Bootstrap'
Write-Log '======================================================='

# ── Admin check ──────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Err 'Not running as administrator.'
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click bootstrap.bat and select "Run as administrator"'
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Prompt for agent passphrase ──────────────────────────────────────────────
Write-Host ''
$Passphrase = Read-Host 'Enter agent passphrase (min 8 characters recommended)'
if ($Passphrase.Length -eq 0) {
    Write-Err 'Passphrase must not be empty.'
    exit 1
}
if ($Passphrase.Length -lt 8) {
    Write-Warn 'Passphrase is shorter than 8 characters. Consider using a stronger passphrase.'
}
Write-Log '[INFO] Passphrase provided - OK'

$PortInput = Read-Host "Enter agent port [$DefaultAgentPort]"
$AgentPort = if ($PortInput -match '^\d+$') { [int]$PortInput } else { $DefaultAgentPort }
Write-Log "[INFO] Agent port: $AgentPort"

# ===========================================================================
#  STEP 1: OpenSSH Server
# ===========================================================================
Write-Step '1/3' 'Enable OpenSSH Server'

try {
    # Check if already installed
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

    if ($sshCapability.State -eq 'Installed') {
        Write-OK 'OpenSSH Server is already installed.'
    } else {
        Write-Log '[INFO] Installing OpenSSH Server...'
        Write-Host '       Installing OpenSSH Server (this may take a minute)...'
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
        Write-OK 'OpenSSH Server installed.'
    }

    # Start and enable the service
    Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service sshd -ErrorAction SilentlyContinue
    Write-OK 'sshd service started and set to automatic.'

    # Set default shell to PowerShell (so SSH sessions get PowerShell, not cmd)
    $regPath = 'HKLM:\SOFTWARE\OpenSSH'
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    $pwshPath = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if ($pwshPath) {
        New-ItemProperty -Path $regPath -Name DefaultShell -Value $pwshPath -PropertyType String -Force | Out-Null
        Write-OK "Default SSH shell set to PowerShell."
    }

    # Firewall rule for SSH
    Remove-NetFirewallRule -DisplayName 'OpenSSH-Server-Bootstrap' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'OpenSSH-Server-Bootstrap' `
        -Direction Inbound -Protocol TCP -LocalPort $DefaultSSHPort -Action Allow | Out-Null
    Write-OK "Firewall rule added for port $DefaultSSHPort (SSH)."

} catch {
    Write-Err "OpenSSH setup failed: $_"
    Write-Warn 'Continuing with remaining steps...'
}

# ===========================================================================
#  STEP 2: Shutdown Agent
# ===========================================================================
Write-Step '2/3' 'Install Shutdown Agent'

# Find Python
$PythonCmd = $null
foreach ($cmd in @('python', 'python3')) {
    try {
        $ver = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $PythonCmd = $cmd
            Write-OK "Python found: $cmd -> $ver"
            break
        }
    } catch { }
}

$AgentInstalled = $false

if ($PythonCmd) {
    # Look for shutdown_agent.py in the same directory as this script
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $AgentScript = Join-Path $ScriptDir 'shutdown_agent.py'

    if (Test-Path $AgentScript) {
        Write-Log "[INFO] Found shutdown_agent.py at: $AgentScript"

        # Set environment variable for passphrase
        try {
            [System.Environment]::SetEnvironmentVariable(
                'NETWORK_PC_MANAGER_AGENT_PASSPHRASE', $Passphrase, 'Machine')
            Write-OK 'Passphrase stored in system environment variable.'
        } catch {
            Write-Warn "Could not set environment variable: $_"
        }

        # Create scheduled task
        try {
            Unregister-ScheduledTask -TaskName $LegacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

            $PythonFull = (Get-Command $PythonCmd -ErrorAction Stop).Source
            $action   = New-ScheduledTaskAction -Execute $PythonFull -Argument "`"$AgentScript`" --port $AgentPort"
            $trigger  = New-ScheduledTaskTrigger -AtStartup
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

            Register-ScheduledTask -TaskName $TaskName `
                -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

            Write-OK "Scheduled task '$TaskName' created (runs at startup)."
        } catch {
            Write-Warn "Could not create scheduled task: $_"
        }

        # Firewall rule for agent
        Remove-NetFirewallRule -DisplayName 'NetworkPCManager-Agent' -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName 'NetworkPCManager-Agent' `
            -Direction Inbound -Protocol TCP -LocalPort $AgentPort -Action Allow | Out-Null
        Write-OK "Firewall rule added for port $AgentPort (agent)."

        # Start agent now
        try {
            Start-Process -FilePath $PythonFull -ArgumentList "`"$AgentScript`" --port $AgentPort --passphrase `"$Passphrase`"" -WindowStyle Minimized
            Write-OK 'Agent started.'
            $AgentInstalled = $true
        } catch {
            Write-Warn "Could not start agent: $_"
        }
    } else {
        Write-Warn "shutdown_agent.py not found in $ScriptDir"
        Write-Warn 'Skipping agent installation. You can install it later with setup_agent.bat.'
    }
} else {
    Write-Warn 'Python not found in PATH. Skipping agent installation.'
    Write-Warn 'Install Python from https://www.python.org/downloads/ and run setup_agent.bat later.'
}

# ===========================================================================
#  STEP 3: Software Packages via winget
# ===========================================================================
Write-Step '3/3' 'Install Software Packages'

# Check for winget
$WingetAvailable = $false
try {
    $wingetVer = winget --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $WingetAvailable = $true
        Write-OK "winget found: $wingetVer"
    }
} catch { }

if (-not $WingetAvailable) {
    Write-Err 'winget is not available on this system.'
    Write-Host '       winget is included with Windows 10 (1809+) and Windows 11.'
    Write-Host '       Install "App Installer" from the Microsoft Store if missing.'
    Write-Host ''
    Write-Host '       Skipping software installation.'
} else {
    # Load package list from setup_packages.json (same directory as this script)
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $PackageFile = Join-Path $ScriptDir 'setup_packages.json'
    $Packages = @()

    if (Test-Path $PackageFile) {
        try {
            $config = Get-Content $PackageFile -Raw | ConvertFrom-Json
            $Packages = $config.packages
            Write-OK "Loaded $($Packages.Count) packages from setup_packages.json"
        } catch {
            Write-Warn "Could not parse setup_packages.json: $_"
        }
    } else {
        Write-Warn "setup_packages.json not found in $ScriptDir"
        Write-Warn 'Using built-in default package list.'
        # Fallback: built-in defaults
        $Packages = @(
            @{ name = 'Google Chrome';  winget_id = 'Google.Chrome' },
            @{ name = '7-Zip';          winget_id = '7zip.7zip' },
            @{ name = 'VLC';            winget_id = 'VideoLAN.VLC' },
            @{ name = 'Steam';          winget_id = 'Valve.Steam' },
            @{ name = 'Discord';        winget_id = 'Discord.Discord' }
        )
    }

    if ($Packages.Count -eq 0) {
        Write-Warn 'No packages to install.'
    } else {
        Write-Host ''
        Write-Host "       Installing $($Packages.Count) packages..."
        Write-Host ''

        $succeeded = 0
        $failed = 0
        $skipped = 0

        foreach ($pkg in $Packages) {
            $name = $pkg.name
            $id = $pkg.winget_id
            Write-Host "       [$($succeeded + $failed + $skipped + 1)/$($Packages.Count)] Installing $name ($id)..." -NoNewline
            Write-Log "[INFO] Installing: $name ($id)"

            try {
                $output = winget install $id `
                    --accept-source-agreements `
                    --accept-package-agreements `
                    --disable-interactivity `
                    --silent 2>&1

                $exitCode = $LASTEXITCODE
                $outputStr = ($output | Out-String)

                if ($exitCode -eq 0) {
                    if ($outputStr -match 'already installed') {
                        Write-Host ' SKIPPED (already installed)' -ForegroundColor DarkGray
                        Write-Log "[INFO] $name - already installed"
                        $skipped++
                    } else {
                        Write-Host ' OK' -ForegroundColor Green
                        Write-Log "[OK] $name installed successfully"
                        $succeeded++
                    }
                } elseif ($outputStr -match 'already installed') {
                    Write-Host ' SKIPPED (already installed)' -ForegroundColor DarkGray
                    Write-Log "[INFO] $name - already installed"
                    $skipped++
                } else {
                    Write-Host ' FAILED' -ForegroundColor Red
                    Write-Log "[ERROR] $name failed (exit code $exitCode): $outputStr"
                    $failed++
                }
            } catch {
                Write-Host ' FAILED' -ForegroundColor Red
                Write-Log "[ERROR] $name failed: $_"
                $failed++
            }
        }

        Write-Host ''
        Write-Log "[INFO] Package summary: $succeeded installed, $skipped already present, $failed failed"
    }
}

# ===========================================================================
#  Summary
# ===========================================================================
Write-Host ''
Write-Host '======================================================='
Write-Host '  Bootstrap Complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host "  OpenSSH Server   : Enabled (port $DefaultSSHPort)"
if ($AgentInstalled) {
    Write-Host "  Shutdown Agent   : Running (port $AgentPort)"
} else {
    Write-Host '  Shutdown Agent   : NOT installed (see warnings above)'
}
if ($WingetAvailable -and $Packages.Count -gt 0) {
    Write-Host "  Software         : $succeeded installed, $skipped skipped, $failed failed"
}
Write-Host ''
Write-Host "  This PC's IP     : $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } | Select-Object -First 1).IPAddress)"
Write-Host "  SSH access       : ssh $env:USERNAME@<this-ip>"
Write-Host ''
Write-Host "  Log file         : $LogFile"
Write-Host ''

Write-Log '[INFO] Bootstrap complete.'
