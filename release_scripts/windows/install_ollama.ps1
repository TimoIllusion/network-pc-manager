# Network PC Manager - Ollama LLM Installer
# Installs Ollama and configures it to serve an OpenAI-compatible LLM endpoint
# on the local network (no login required).
#
# Run as Administrator: Right-click > "Run as administrator"
# Or via install_ollama.bat which handles ExecutionPolicy automatically.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile       = Join-Path $ScriptDir 'install_ollama.log'
$FirewallRule  = 'NetworkPCManager-Ollama'
$OllamaPort    = 11434
$ServiceName   = 'NetworkPCManager-Ollama'
$DefaultModel  = 'llama3.2:3b'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - Ollama LLM Installer'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Ollama LLM Installer'
Write-Log '======================================================='

# ── Admin check ──────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log '[ERROR] Not running as administrator.'
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click install_ollama.bat and select "Run as administrator"'
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Check if Ollama is already installed ─────────────────────────────────────
$ollamaPath = Get-Command 'ollama' -ErrorAction SilentlyContinue
if ($ollamaPath) {
    Write-Log "[INFO] Ollama already installed at: $($ollamaPath.Source)"
    Write-Host "[INFO] Ollama is already installed." -ForegroundColor Green
} else {
    # ── Install Ollama via winget ────────────────────────────────────────────
    $hasWinget = Get-Command 'winget' -ErrorAction SilentlyContinue
    if (-not $hasWinget) {
        Write-Log '[ERROR] winget not found. Please install App Installer from the Microsoft Store.'
        Write-Host '[ERROR] winget is not available on this system.' -ForegroundColor Red
        Write-Host '  Install "App Installer" from the Microsoft Store, then retry.'
        exit 1
    }

    Write-Log '[INFO] Installing Ollama via winget...'
    Write-Host '[INFO] Installing Ollama via winget (this may take a minute)...'
    try {
        winget install --id Ollama.Ollama --exact --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Log "[WARN] winget exited with code $LASTEXITCODE"
        }
        Write-Log '[INFO] Ollama installed via winget.'
        Write-Host '[INFO] Ollama installed successfully.'
    } catch {
        Write-Log "[ERROR] Ollama installation failed: $_"
        Write-Host "[ERROR] Ollama installation failed: $_" -ForegroundColor Red
        Write-Host '  You can install Ollama manually: winget install Ollama.Ollama'
        exit 1
    }

    # Refresh PATH so we can find ollama
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# ── Configure Ollama to listen on all interfaces ────────────────────────────
Write-Log '[INFO] Configuring OLLAMA_HOST=0.0.0.0 (listen on all interfaces)...'
try {
    [System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', '0.0.0.0', 'Machine')
    $env:OLLAMA_HOST = '0.0.0.0'
    Write-Log '[INFO] OLLAMA_HOST set - OK'
    Write-Host '[INFO] Ollama configured to listen on all network interfaces.'
} catch {
    Write-Log "[WARN] Could not set OLLAMA_HOST: $_"
    Write-Host "[WARN] Could not set OLLAMA_HOST environment variable: $_" -ForegroundColor Yellow
}

# ── Firewall rule ────────────────────────────────────────────────────────────
Write-Log "[INFO] Adding firewall rule for Ollama port $OllamaPort..."
try {
    Remove-NetFirewallRule -DisplayName $FirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $FirewallRule `
        -Direction Inbound -Protocol TCP -LocalPort $OllamaPort -Action Allow | Out-Null
    Write-Log '[INFO] Firewall rule added - OK'
    Write-Host '[INFO] Firewall rule added for port 11434.'
} catch {
    Write-Log "[WARN] Could not add firewall rule: $_"
    Write-Host "[WARN] Could not add firewall rule. You may need to allow port $OllamaPort manually." -ForegroundColor Yellow
}

# ── Create scheduled task to run Ollama serve at startup (no login) ──────────
Write-Log '[INFO] Creating scheduled task for Ollama serve...'
try {
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue

    # Find ollama.exe
    $ollamaExe = (Get-Command 'ollama' -ErrorAction SilentlyContinue).Source
    if (-not $ollamaExe) {
        # Common install location
        $ollamaExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
        if (-not (Test-Path $ollamaExe)) {
            $ollamaExe = "$env:ProgramFiles\Ollama\ollama.exe"
        }
    }

    if (Test-Path $ollamaExe) {
        $action    = New-ScheduledTaskAction -Execute $ollamaExe -Argument 'serve'
        $trigger   = New-ScheduledTaskTrigger -AtStartup
        $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

        Register-ScheduledTask -TaskName $ServiceName `
            -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

        Write-Log "[INFO] Scheduled task '$ServiceName' created - OK"
        Write-Host "[INFO] Scheduled task created (Ollama serve runs at startup, no login required)."
    } else {
        Write-Log '[WARN] Could not find ollama.exe for scheduled task.'
        Write-Host '[WARN] Could not locate ollama.exe. Ollama may run via its own service.' -ForegroundColor Yellow
    }
} catch {
    Write-Log "[WARN] Could not create scheduled task: $_"
    Write-Host "[WARN] Could not create scheduled task: $_" -ForegroundColor Yellow
}

# ── Start Ollama serve now ───────────────────────────────────────────────────
Write-Log '[INFO] Starting Ollama serve...'
try {
    # Kill any existing instance
    Stop-Process -Name 'ollama' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden
    Write-Log '[INFO] Ollama serve started.'
    Write-Host '[INFO] Ollama serve started.'
    Start-Sleep -Seconds 3
} catch {
    Write-Log "[WARN] Could not start Ollama serve: $_"
    Write-Host "[WARN] Could not start Ollama serve: $_" -ForegroundColor Yellow
}

# ── Prompt for model to pull ─────────────────────────────────────────────────
Write-Host ''
$ModelInput = Read-Host "Enter model to pull [$DefaultModel]"
$Model = if ($ModelInput.Trim()) { $ModelInput.Trim() } else { $DefaultModel }
Write-Log "[INFO] Pulling model: $Model"

Write-Host ''
Write-Host "[INFO] Pulling model '$Model' - this may take a while..." -ForegroundColor Cyan
try {
    & ollama pull $Model 2>&1 | ForEach-Object { Write-Host $_ }
    Write-Log "[INFO] Model '$Model' pulled successfully."
    Write-Host "[INFO] Model '$Model' ready." -ForegroundColor Green
} catch {
    Write-Log "[WARN] Could not pull model: $_"
    Write-Host "[WARN] Could not pull model: $_" -ForegroundColor Yellow
    Write-Host "  You can pull it later with: ollama pull $Model"
}

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Log '[INFO] Ollama installation complete.'
Write-Host ''
Write-Host '======================================================='
Write-Host '  Ollama Installation Complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Ollama API      : http://localhost:$OllamaPort"
Write-Host "  OpenAI-compat   : http://localhost:$OllamaPort/v1"
Write-Host "  Model           : $Model"
Write-Host '  Auto-starts at system startup (no login required).'
Write-Host ''
Write-Host '  Other devices on your network can use this endpoint at:'
Write-Host "    http://<this-pc-ip>:$OllamaPort/v1"
Write-Host ''
Write-Host "  Install log: $LogFile"
Write-Host ''
