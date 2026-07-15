#!/usr/bin/env bash
set -euo pipefail

# ─── Network PC Manager - Shutdown Agent Updater (Linux standalone) ───────────
# Downloads the latest linux release zip from GitHub, replaces the installed
# binary, and restarts the service. No Python required.
#
# Usage: sudo bash update.sh [-port <port>] [-force]
#   -port   Port the agent is listening on (default: 9876), used for version check
#   -force  Update even if already on the latest version

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

INSTALL_DIR="/opt/network-pc-manager"
SERVICE_NAME="network-pc-manager-agent"
REPO_OWNER="TimoIllusion"
REPO_NAME="network-pc-manager"
PORT=9876
FORCE=0

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -port)  PORT="$2"; shift 2 ;;
        -force) FORCE=1; shift ;;
        *)      warn "Unknown argument: $1"; shift ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    info "Re-running as root (sudo)..."
    exec sudo bash "$0" "$@"
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Network PC Manager - Shutdown Agent Update ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo

# ─── Check current version ────────────────────────────────────────────────────
CURRENT_VERSION=""
if command -v curl &>/dev/null; then
    info "Querying agent health at http://localhost:${PORT}/health ..."
    HEALTH=$(curl -fsS --max-time 5 "http://localhost:${PORT}/health" 2>/dev/null || true)
    if [ -n "$HEALTH" ]; then
        CURRENT_VERSION=$(echo "$HEALTH" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        info "Current installed version: ${CURRENT_VERSION:-unknown}"
    else
        warn "Could not reach agent on port ${PORT} - will update anyway."
    fi
else
    warn "curl not found - skipping version check."
fi

# ─── Fetch latest release from GitHub ────────────────────────────────────────
info "Fetching latest release from GitHub (${REPO_OWNER}/${REPO_NAME})..."
if ! command -v curl &>/dev/null; then
    error "curl is required but not installed. Install it with: apt-get install -y curl"
fi

API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
RELEASE_JSON=$(curl -fsS --max-time 30 -H "User-Agent: NetworkPCManager-Updater" "$API_URL" \
    || error "Could not reach GitHub API. Check your internet connection.")

LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
info "Latest version: ${LATEST_TAG:-unknown}"

# ─── Version comparison ───────────────────────────────────────────────────────
if [ "$FORCE" -eq 0 ] && [ -n "$CURRENT_VERSION" ] && [ -n "$LATEST_TAG" ]; then
    if [ "$CURRENT_VERSION" = "$LATEST_TAG" ] || [ "v$CURRENT_VERSION" = "$LATEST_TAG" ]; then
        info "Already on the latest version. Nothing to do."
        echo "  Run with -force to reinstall anyway."
        exit 0
    fi
fi

# ─── Find linux-x64 asset ────────────────────────────────────────────────────
ASSET_URL=$(echo "$RELEASE_JSON" \
    | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | grep -i 'linux.*x64.*\.zip' \
    | head -1 \
    | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')

if [ -z "$ASSET_URL" ]; then
    error "No linux-x64 zip asset found in the latest release."
fi

info "Download URL: $ASSET_URL"

# ─── Download zip ─────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
ZIP_PATH="$TMPDIR/release.zip"
info "Downloading..."
curl -fsS --max-time 120 -L -o "$ZIP_PATH" "$ASSET_URL" || error "Download failed."

# ─── Stop agent ───────────────────────────────────────────────────────────────
info "Stopping agent..."
if command -v systemctl &>/dev/null; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
else
    pkill -f "shutdown_agent" 2>/dev/null || true
fi
sleep 1

# ─── Extract and replace binary ───────────────────────────────────────────────
EXTRACT_DIR="$TMPDIR/extracted"
mkdir -p "$EXTRACT_DIR"
if command -v unzip &>/dev/null; then
    unzip -q -o "$ZIP_PATH" -d "$EXTRACT_DIR"
else
    # Python fallback for extraction (python3 is usually present even on minimal systems)
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ZIP_PATH" "$EXTRACT_DIR"
fi

NEW_BIN=$(find "$EXTRACT_DIR" -type f -name "shutdown_agent" | head -1)
if [ -z "$NEW_BIN" ]; then
    error "shutdown_agent binary not found in the downloaded zip."
fi

info "Installing updated binary to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
cp -f "$NEW_BIN" "$INSTALL_DIR/shutdown_agent"
chmod +x "$INSTALL_DIR/shutdown_agent"
info "Binary updated."

# ─── Cleanup temp files ───────────────────────────────────────────────────────
rm -rf "$TMPDIR"

# ─── Restart agent ────────────────────────────────────────────────────────────
info "Restarting agent..."
if command -v systemctl &>/dev/null; then
    systemctl restart "$SERVICE_NAME" 2>/dev/null || warn "Could not restart via systemctl."
else
    # Re-launch via the same mechanism cron uses
    warn "No systemd - starting agent directly. (A cron @reboot entry, if present, will also start it on next boot.)"
    nohup "$INSTALL_DIR/shutdown_agent" --port "$PORT" &>/var/log/network-pc-manager-agent.log &
    info "Agent started (PID: $!)."
fi

# ─── Verify ────────────────────────────────────────────────────────────────────
sleep 2
if command -v curl &>/dev/null; then
    HEALTH=$(curl -fsS --max-time 5 "http://localhost:${PORT}/health" 2>/dev/null || true)
    if [ -n "$HEALTH" ]; then
        NEW_VERSION=$(echo "$HEALTH" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        info "Agent running version: ${NEW_VERSION:-unknown}"
    else
        warn "Could not verify new version (agent may still be starting)."
    fi
fi

echo
info "Update complete!"
echo -e "  Updated to: ${CYAN}${LATEST_TAG:-unknown}${NC}"
echo -e "  Install dir: ${CYAN}${INSTALL_DIR}${NC}"
echo
