# Network PC Manager - Shutdown Agent Updater
# Run as Administrator: Right-click > "Run as administrator"
# Or via update.bat which handles ExecutionPolicy automatically.
#
# Usage: update.ps1 [-Port <port>] [-Force]
#   -Port   Port the agent is listening on (default: 9876)
#   -Force  Update even if already on the latest version

#Requires -Version 5.1

param(
    [int]$Port = 9876,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$LogFile    = "$env:TEMP\NetworkPCManager_update.log"
$InstallDir = "$env:ProgramFiles\NetworkPCManager"
$TaskName   = 'NetworkPCManager-ShutdownAgent'
$RepoOwner  = 'TimoIllusion'
$RepoName   = 'network-pc-manager'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - Shutdown Agent Updater'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - Shutdown Agent Updater'
Write-Log '======================================================='

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log '[ERROR] Not running as administrator.'
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click update.bat and select "Run as administrator"'
    Write-Host ''
    Write-Host "  Log saved to: $LogFile"
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ── Check current installed version ───────────────────────────────────────────
$currentVersion = $null
Write-Log "[INFO] Querying agent health at http://localhost:$Port/health ..."
try {
    $health = Invoke-RestMethod -Uri "http://localhost:$Port/health" -TimeoutSec 5 -ErrorAction Stop
    $currentVersion = $health.version
    Write-Log "[INFO] Current installed version: $currentVersion"
    Write-Host "[INFO] Current version : $currentVersion"
} catch {
    Write-Log "[WARN] Could not reach agent on port $Port : $_"
    Write-Host "[WARN] Agent not responding on port $Port - will update anyway." -ForegroundColor Yellow
}

# ── Fetch latest release from GitHub ─────────────────────────────────────────
Write-Log "[INFO] Fetching latest release from GitHub ($RepoOwner/$RepoName)..."
try {
    $apiUrl  = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    $headers = @{ 'User-Agent' = 'NetworkPCManager-Updater' }
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30 -ErrorAction Stop
} catch {
    Write-Log "[ERROR] Failed to fetch release info: $_"
    Write-Host '[ERROR] Could not reach GitHub API. Check your internet connection.' -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    exit 1
}

$latestTag = $release.tag_name
Write-Log "[INFO] Latest release tag: $latestTag"
Write-Host "[INFO] Latest version  : $latestTag"

# ── Version comparison ────────────────────────────────────────────────────────
if (-not $Force -and $currentVersion -and ($currentVersion -eq $latestTag -or "v$currentVersion" -eq $latestTag)) {
    Write-Log '[INFO] Already on the latest version. Nothing to do.'
    Write-Host ''
    Write-Host '[INFO] Already up to date!' -ForegroundColor Green
    Write-Host "  Run with -Force to reinstall anyway."
    Write-Host ''
    exit 0
}

# ── Find win-x64 asset ────────────────────────────────────────────────────────
$asset = $release.assets | Where-Object { $_.name -like '*-win-x64.zip' } | Select-Object -First 1
if (-not $asset) {
    Write-Log '[ERROR] No win-x64 zip asset found in the latest release.'
    Write-Host '[ERROR] No Windows release asset found.' -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Log "[INFO] Download URL: $downloadUrl"

# ── Download zip ──────────────────────────────────────────────────────────────
$TempDir = Join-Path $env:TEMP "NetworkPCManager_update_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$ZipPath = Join-Path $TempDir $asset.name

Write-Log "[INFO] Downloading $($asset.name) ..."
Write-Host "[INFO] Downloading update ..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    Write-Log "[INFO] Download complete: $ZipPath"
} catch {
    Write-Log "[ERROR] Download failed: $_"
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ── Stop running agent ────────────────────────────────────────────────────────
Write-Log '[INFO] Stopping agent...'
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Stop-Process -Name 'shutdown_agent' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Write-Log '[INFO] Agent stopped.'

# ── Extract and replace executable ────────────────────────────────────────────
Write-Log "[INFO] Extracting $($asset.name) ..."
$ExtractDir = Join-Path $TempDir 'extracted'
Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

$NewExe = Get-ChildItem -Path $ExtractDir -Filter 'shutdown_agent.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
if (-not $NewExe) {
    Write-Log "[ERROR] shutdown_agent.exe not found in the downloaded zip."
    Write-Host '[ERROR] Update package is missing shutdown_agent.exe.' -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Log "[INFO] Installing updated executable to $InstallDir ..."
try {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path $NewExe -Destination "$InstallDir\shutdown_agent.exe" -Force
    Write-Log '[INFO] Executable updated successfully.'
    Write-Host '[INFO] Executable updated.'
} catch {
    Write-Log "[ERROR] Failed to replace executable: $_"
    Write-Host "[ERROR] Failed to replace executable: $_" -ForegroundColor Red
    Write-Host "  Log saved to: $LogFile"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ── Cleanup temp files ────────────────────────────────────────────────────────
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

# ── Restart agent ─────────────────────────────────────────────────────────────
Write-Log '[INFO] Starting agent...'
try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Log '[INFO] Agent started via scheduled task.'
    Write-Host '[INFO] Agent restarted.'
} catch {
    Write-Log "[WARN] Could not start scheduled task: $_"
    Write-Host "[WARN] Could not start via scheduled task. Starting directly..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath "$InstallDir\shutdown_agent.exe" -WindowStyle Minimized
        Write-Log '[INFO] Agent started directly.'
    } catch {
        Write-Log "[WARN] Could not start agent: $_"
        Write-Host "[WARN] Could not start agent automatically. Please start it manually." -ForegroundColor Yellow
    }
}

# ── Verify new version ────────────────────────────────────────────────────────
Start-Sleep -Seconds 2
try {
    $health = Invoke-RestMethod -Uri "http://localhost:$Port/health" -TimeoutSec 5 -ErrorAction Stop
    $newVersion = $health.version
    Write-Log "[INFO] Agent running version: $newVersion"
    Write-Host "[INFO] Running version : $newVersion" -ForegroundColor Green
} catch {
    Write-Log "[WARN] Could not verify new version (agent may still be starting): $_"
    Write-Host "[WARN] Could not verify new version - agent may still be starting." -ForegroundColor Yellow
}

Write-Log '[INFO] Update complete.'
Write-Host ''
Write-Host '======================================================='
Write-Host '  Update complete!'
Write-Host '======================================================='
Write-Host ''
Write-Host "  Updated to : $latestTag"
Write-Host "  Install dir: $InstallDir"
Write-Host ''
Write-Host "  Update log: $LogFile"
Write-Host ''
