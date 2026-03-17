# Network PC Manager - PC Bootstrap (Setup Agent + Install Software)
# ==================================================================
# Run as Administrator: Right-click > "Run as administrator"
# Or via bootstrap.bat which handles ExecutionPolicy automatically.
#
# This script:
#   1. Runs the shutdown agent installer (install.ps1)
#   2. Installs software packages via winget from setup_packages.json

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $ScriptDir 'bootstrap.log'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '======================================================='
Write-Host '  Network PC Manager - PC Bootstrap'
Write-Host '======================================================='
Write-Host ''
Write-Host "  This script will:"
Write-Host "    1. Install the shutdown agent (via install.ps1)"
Write-Host "    2. Install software packages via winget"
Write-Host ''
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '======================================================='
Write-Log '  Network PC Manager - PC Bootstrap'
Write-Log '======================================================='

# ── Admin check ──────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host '[ERROR] This script must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  How to fix:'
    Write-Host '    Right-click bootstrap.bat and select "Run as administrator"'
    Write-Host ''
    exit 1
}
Write-Log '[INFO] Running as administrator - OK'

# ===========================================================================
#  STEP 1: Run the agent installer
# ===========================================================================
Write-Host ''
Write-Host '-------------------------------------------------------'
Write-Host '  Step 1/2: Install Shutdown Agent'
Write-Host '-------------------------------------------------------'
Write-Log '=== STEP 1: Install Shutdown Agent ==='

$InstallerScript = Join-Path $ScriptDir 'install.ps1'

if (Test-Path $InstallerScript) {
    Write-Log "[INFO] Running install.ps1 from: $InstallerScript"
    try {
        & $InstallerScript
        Write-Log '[INFO] Agent installer completed.'
    } catch {
        Write-Log "[WARN] Agent installer had issues: $_"
        Write-Host "[WARN] Agent installer had issues: $_" -ForegroundColor Yellow
    }
} else {
    Write-Log "[WARN] install.ps1 not found at: $InstallerScript"
    Write-Host "[WARN] install.ps1 not found. Skipping agent installation." -ForegroundColor Yellow
    Write-Host "       Make sure bootstrap.bat is in the same folder as install.ps1"
}

# ===========================================================================
#  STEP 2: Install software packages via winget
# ===========================================================================
Write-Host ''
Write-Host '-------------------------------------------------------'
Write-Host '  Step 2/2: Install Software Packages'
Write-Host '-------------------------------------------------------'
Write-Log '=== STEP 2: Install Software Packages ==='

# Check for winget
$WingetAvailable = $false
try {
    $wingetVer = winget --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $WingetAvailable = $true
        Write-Host "[INFO] winget found: $wingetVer"
        Write-Log "[INFO] winget found: $wingetVer"
    }
} catch { }

if (-not $WingetAvailable) {
    Write-Host '[ERROR] winget is not available.' -ForegroundColor Red
    Write-Host '        Install "App Installer" from the Microsoft Store.'
    Write-Log '[ERROR] winget not available. Skipping software installation.'
} else {
    # Load package list
    $PackageFile = Join-Path $ScriptDir 'setup_packages.json'
    $Packages = @()

    if (Test-Path $PackageFile) {
        try {
            $config = Get-Content $PackageFile -Raw | ConvertFrom-Json
            $Packages = $config.packages
            Write-Host "[INFO] Loaded $($Packages.Count) packages from setup_packages.json"
            Write-Log "[INFO] Loaded $($Packages.Count) packages from setup_packages.json"
        } catch {
            Write-Host "[WARN] Could not parse setup_packages.json: $_" -ForegroundColor Yellow
            Write-Log "[WARN] Could not parse setup_packages.json: $_"
        }
    } else {
        Write-Host "[WARN] setup_packages.json not found in $ScriptDir" -ForegroundColor Yellow
        Write-Log "[WARN] setup_packages.json not found"
    }

    if ($Packages.Count -eq 0) {
        Write-Host '[INFO] No packages to install.'
        Write-Log '[INFO] No packages to install.'
    } else {
        Write-Host ''
        $succeeded = 0
        $failed = 0
        $skipped = 0

        foreach ($pkg in $Packages) {
            $name = $pkg.name
            $id = $pkg.winget_id
            $idx = $succeeded + $failed + $skipped + 1
            Write-Host "  [$idx/$($Packages.Count)] $name ($id)..." -NoNewline
            Write-Log "[INFO] Installing: $name ($id)"

            try {
                $output = winget install $id `
                    --accept-source-agreements `
                    --accept-package-agreements `
                    --disable-interactivity `
                    --silent 2>&1

                $exitCode = $LASTEXITCODE
                $outputStr = ($output | Out-String)

                if ($outputStr -match 'already installed') {
                    Write-Host ' SKIPPED (already installed)' -ForegroundColor DarkGray
                    Write-Log "[INFO] $name - already installed"
                    $skipped++
                } elseif ($exitCode -eq 0) {
                    Write-Host ' OK' -ForegroundColor Green
                    Write-Log "[OK] $name installed"
                    $succeeded++
                } else {
                    Write-Host ' FAILED' -ForegroundColor Red
                    Write-Log "[ERROR] $name failed (exit $exitCode): $outputStr"
                    $failed++
                }
            } catch {
                Write-Host ' FAILED' -ForegroundColor Red
                Write-Log "[ERROR] $name failed: $_"
                $failed++
            }
        }

        Write-Host ''
        Write-Log "[INFO] Summary: $succeeded installed, $skipped already present, $failed failed"
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
if ($WingetAvailable -and $Packages.Count -gt 0) {
    Write-Host "  Software: $succeeded installed, $skipped skipped, $failed failed"
}
Write-Host "  Log file: $LogFile"
Write-Host ''

Write-Log '[INFO] Bootstrap complete.'
