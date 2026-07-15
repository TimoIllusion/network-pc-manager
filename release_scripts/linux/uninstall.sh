#!/usr/bin/env bash
set -euo pipefail

# ─── Network PC Manager - Shutdown Agent Uninstaller (Linux) ─────────────────
# Removes the systemd service (or cron entry) and the installed binary.
# Usage: sudo bash uninstall.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

INSTALL_DIR="/opt/network-pc-manager"
SERVICE_NAME="network-pc-manager-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/network-pc-manager-agent.log"

if [[ $EUID -ne 0 ]]; then
    info "Re-running as root (sudo)..."
    exec sudo bash "$0" "$@"
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Network PC Manager - Shutdown Agent Remove ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo

# ─── Stop and remove systemd service ─────────────────────────────────────────
if command -v systemctl &>/dev/null; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "Stopping systemd service..."
        systemctl stop "$SERVICE_NAME" || true
    fi
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "Disabling systemd service..."
        systemctl disable "$SERVICE_NAME" || true
    fi
    if [ -f "$SERVICE_FILE" ]; then
        info "Removing service file: $SERVICE_FILE"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    # Also clean up the legacy name
    if [ -f "/etc/systemd/system/wol-shutdown-agent.service" ]; then
        warn "Removing legacy service 'wol-shutdown-agent'..."
        systemctl stop "wol-shutdown-agent" 2>/dev/null || true
        systemctl disable "wol-shutdown-agent" 2>/dev/null || true
        rm -f "/etc/systemd/system/wol-shutdown-agent.service"
        systemctl daemon-reload
    fi
else
    # ── Fallback: cron ──
    if crontab -l 2>/dev/null | grep -qF "shutdown_agent"; then
        info "Removing cron entry..."
        crontab -l 2>/dev/null | grep -vF "shutdown_agent" | crontab - || true
    fi
    if pgrep -f "shutdown_agent" &>/dev/null; then
        info "Stopping running agent..."
        pkill -f "shutdown_agent" || true
    fi
fi

# ─── Remove binary ────────────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    info "Removing install directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    info "Installed files removed."
else
    info "Install directory not found (already removed or never installed)."
fi

# ─── Optionally remove log file ───────────────────────────────────────────────
if [ -f "$LOG_FILE" ]; then
    read -rp "Remove log file $LOG_FILE? [y/N] " RMLOG
    if [[ "${RMLOG,,}" == "y" || "${RMLOG,,}" == "yes" ]]; then
        rm -f "$LOG_FILE"
        info "Log file removed."
    else
        info "Log file kept at $LOG_FILE"
    fi
fi

echo
info "Uninstall complete!"
echo
