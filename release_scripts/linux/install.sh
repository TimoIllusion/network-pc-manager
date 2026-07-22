#!/usr/bin/env bash
set -euo pipefail

# ─── Network PC Manager - Shutdown Agent Installer (Linux) ──────────────────
# For use with the standalone binary release (no Python required).
# Usage:  sudo bash install.sh   (or just: bash install.sh, it will re-exec as root)
#
# Installs the shutdown_agent binary as a systemd service (or cron @reboot
# fallback) so it starts automatically on boot. Works on Debian/Ubuntu, Proxmox,
# and other systemd-based Linux distributions.

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="$SCRIPT_DIR/shutdown_agent"
INSTALL_DIR="/opt/network-pc-manager"
SERVICE_NAME="network-pc-manager-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/network-pc-manager-agent.log"

# ─── Root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    info "Re-running as root (sudo)..."
    exec sudo bash "$0" "$@"
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Network PC Manager - Shutdown Agent Setup  ║${NC}"
echo -e "${CYAN}║            (Linux standalone binary)          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo

# ─── Locate binary ────────────────────────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
    error "shutdown_agent binary not found in $SCRIPT_DIR"
fi

# ─── Prompt for configuration ────────────────────────────────────────────────
read -rp "Enter passphrase (min 8 characters recommended): " PASSPHRASE
[ -n "$PASSPHRASE" ] || error "Passphrase must not be empty."
if [ ${#PASSPHRASE} -lt 8 ]; then
    warn "Passphrase is shorter than 8 characters. Consider using a stronger passphrase."
fi

read -rp "Enter port [9876]: " PORT
PORT="${PORT:-9876}"

echo
echo "  File sync allows uploading/downloading save games between PCs."
echo "  Enter comma-separated directories to allow, or leave empty to disable."
echo "  Example: /home/user/saves,/home/user/.local/share/GameName"
read -rp "Sync directories (comma-separated, empty to skip): " SYNC_DIRS

SYNC_DIRS_ENV=""
if [ -n "$SYNC_DIRS" ]; then
    SYNC_DIRS_ENV="Environment=NETWORK_PC_MANAGER_SYNC_DIRS=${SYNC_DIRS}"
    info "File sync enabled for: $SYNC_DIRS"
fi

# ─── Install binary and source files ──────────────────────────────────────────
info "Installing files to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp -f "$BINARY" "$INSTALL_DIR/shutdown_agent" 2>/dev/null || true
chmod +x "$INSTALL_DIR/shutdown_agent" 2>/dev/null || true

if [ -f "$SCRIPT_DIR/shutdown_agent.py" ]; then
    cp -f "$SCRIPT_DIR/shutdown_agent.py" "$INSTALL_DIR/shutdown_agent.py"
fi
if [ -f "$SCRIPT_DIR/version.py" ]; then
    cp -f "$SCRIPT_DIR/version.py" "$INSTALL_DIR/version.py"
fi
info "Files installed."

# Ensure log file is writable by the service (runs as root by default)
touch "$LOG_FILE" 2>/dev/null || true

# Determine execution command (fallback to python3 if binary fails GLIBC check)
EXEC_CMD="${INSTALL_DIR}/shutdown_agent --port ${PORT}"
PYTHON_BIN="$(command -v python3 2>/dev/null || true)"

if [ -n "$PYTHON_BIN" ] && [ -f "${INSTALL_DIR}/shutdown_agent.py" ]; then
    if ! "${INSTALL_DIR}/shutdown_agent" --help &>/dev/null; then
        warn "Standalone binary failed execution test (e.g. GLIBC version mismatch); using system python3."
        EXEC_CMD="${PYTHON_BIN} ${INSTALL_DIR}/shutdown_agent.py --port ${PORT}"
    fi
fi

# ─── Install service ─────────────────────────────────────────────────────────
if command -v systemctl &>/dev/null; then
    # ── Remove legacy service if present ──
    if systemctl is-active --quiet "wol-shutdown-agent" 2>/dev/null; then
        warn "Removing legacy service 'wol-shutdown-agent' from older version..."
        systemctl stop "wol-shutdown-agent" 2>/dev/null || true
        systemctl disable "wol-shutdown-agent" 2>/dev/null || true
        rm -f "/etc/systemd/system/wol-shutdown-agent.service"
        systemctl daemon-reload
    fi

    info "Installing systemd service at $SERVICE_FILE ..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Network PC Manager Shutdown Agent
After=network.target

[Service]
Type=simple
Environment=NETWORK_PC_MANAGER_AGENT_PASSPHRASE=${PASSPHRASE}
${SYNC_DIRS_ENV}
ExecStart=${EXEC_CMD}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    info "Service started via systemd (runs at boot, no login required)."

else
    # ── Fallback: cron @reboot ──
    warn "No systemd found. Falling back to cron."
    CRON_CMD="@reboot NETWORK_PC_MANAGER_AGENT_PASSPHRASE='${PASSPHRASE}'${SYNC_DIRS:+ NETWORK_PC_MANAGER_SYNC_DIRS='${SYNC_DIRS}'} ${EXEC_CMD}"
    if crontab -l 2>/dev/null | grep -qF "shutdown_agent"; then
        warn "Cron entry already exists – replacing."
        crontab -l 2>/dev/null | grep -vF "shutdown_agent" | { cat; echo "$CRON_CMD"; } | crontab -
    else
        (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
    fi
    info "Cron entry added. Starting agent now..."
    NETWORK_PC_MANAGER_AGENT_PASSPHRASE="$PASSPHRASE" nohup ${EXEC_CMD} &>"$LOG_FILE" &
    info "Agent started (PID: $!)."
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo
info "Setup complete!"
echo
echo -e "  Agent running on port ${CYAN}${PORT}${NC}"
echo -e "  Binary:   ${CYAN}${INSTALL_DIR}/shutdown_agent${NC}"
echo -e "  Log file: ${CYAN}${LOG_FILE}${NC}"
echo
echo "  Test with:"
echo "    curl -s http://localhost:${PORT}/health"
echo
echo "  To uninstall: sudo bash uninstall.sh"
echo
