#!/usr/bin/env bash
set -euo pipefail

# ─── Network PC Manager - Shutdown Agent Updater (Linux / macOS) ─────────────
# Run this on a target machine to pull the latest source and restart the agent.
# Usage: bash update_agent.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="network-pc-manager-agent"
DAEMON_LABEL="com.network-pc-manager.shutdown-agent"

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Network PC Manager - Shutdown Agent Update ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo

# ─── Pull latest source ───────────────────────────────────────────────────────
info "Pulling latest source in $SCRIPT_DIR ..."
if ! git -C "$SCRIPT_DIR" pull --ff-only; then
    error "git pull failed. Resolve any conflicts or diverged state first."
fi

NEW_VERSION="$(python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR'); from version import __version__; print(__version__)" 2>/dev/null || echo "unknown")"
info "Updated to version: ${CYAN}${NEW_VERSION}${NC}"

# ─── Restart service ──────────────────────────────────────────────────────────
info "Restarting shutdown agent service..."

if [[ "$(uname)" == "Darwin" ]]; then
    PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
    if [ -f "$PLIST_PATH" ]; then
        sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
        sudo launchctl load  "$PLIST_PATH"
        info "Service restarted via launchd."
    else
        warn "launchd plist not found at $PLIST_PATH."
        warn "Run setup_agent.sh first to install the service, then update again."
        exit 1
    fi

elif command -v systemctl &>/dev/null; then
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        sudo systemctl restart "$SERVICE_NAME"
        info "Service restarted via systemd."
    else
        warn "systemd service '$SERVICE_NAME' is not installed."
        warn "Run setup_agent.sh first to install the service, then update again."
        exit 1
    fi

else
    # Fallback: cron-based install — kill and re-launch
    PYTHON3_PATH="$(command -v python3)"
    AGENT_SCRIPT="$SCRIPT_DIR/shutdown_agent.py"

    if pgrep -f "shutdown_agent.py" &>/dev/null; then
        pkill -f "shutdown_agent.py" || true
        sleep 1
    fi

    PASSPHRASE="${NETWORK_PC_MANAGER_AGENT_PASSPHRASE:-}"
    PORT="$(crontab -l 2>/dev/null | grep -oP '(?<=--port )\d+' | head -1 || echo 9876)"

    if [ -z "$PASSPHRASE" ]; then
        warn "NETWORK_PC_MANAGER_AGENT_PASSPHRASE env var not set."
        warn "Export it before running this script, or restart the agent manually."
        exit 1
    fi

    NETWORK_PC_MANAGER_AGENT_PASSPHRASE="$PASSPHRASE" \
        nohup "$PYTHON3_PATH" "$AGENT_SCRIPT" --port "$PORT" \
        &>/var/log/network-pc-manager-agent.log &
    info "Agent restarted (PID: $!)."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo
info "Update complete!"
echo
echo -e "  Version: ${CYAN}${NEW_VERSION}${NC}"
echo
