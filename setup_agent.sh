#!/usr/bin/env bash
set -euo pipefail

# ─── Network PC Manager - Shutdown Agent Setup (Linux / macOS) ───────────────
# Run this on each target machine to install the shutdown agent as a service.
# Usage: bash setup_agent.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SCRIPT="$SCRIPT_DIR/shutdown_agent.py"
SERVICE_NAME="network-pc-manager-agent"

[ -f "$AGENT_SCRIPT" ] || error "shutdown_agent.py not found in $SCRIPT_DIR"
command -v python3 &>/dev/null || error "python3 is required but not installed."

# ─── Prompt for configuration ────────────────────────────────────────────────
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Network PC Manager - Shutdown Agent Setup  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo

read -rp "Enter passphrase (min 8 characters): " PASSPHRASE
[ ${#PASSPHRASE} -ge 8 ] || error "Passphrase must be at least 8 characters."

read -rp "Enter port [9876]: " PORT
PORT="${PORT:-9876}"

# ─── Install based on init system ────────────────────────────────────────────
PYTHON3_PATH="$(command -v python3)"

if [[ "$(uname)" == "Darwin" ]]; then
    # ── Remove legacy LaunchAgent if present (from older versions) ──
    LEGACY_PLIST="$HOME/Library/LaunchAgents/com.wol-proxy.shutdown-agent.plist"
    if [ -f "$LEGACY_PLIST" ]; then
        warn "Removing legacy LaunchAgent from older version..."
        launchctl unload "$LEGACY_PLIST" 2>/dev/null || true
        rm -f "$LEGACY_PLIST"
    fi

    # ── macOS: launchd daemon (runs at boot, no login required) ──
    DAEMON_LABEL="com.network-pc-manager.shutdown-agent"
    PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
    info "Installing launchd daemon at $PLIST_PATH (requires sudo)..."
    sudo tee "$PLIST_PATH" > /dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${DAEMON_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PYTHON3_PATH}</string>
        <string>${AGENT_SCRIPT}</string>
        <string>--port</string>
        <string>${PORT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NETWORK_PC_MANAGER_AGENT_PASSPHRASE</key>
        <string>${PASSPHRASE}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/network-pc-manager-agent.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/network-pc-manager-agent.log</string>
</dict>
</plist>
PLIST
    sudo chown root:wheel "$PLIST_PATH"
    sudo chmod 644 "$PLIST_PATH"
    sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
    sudo launchctl load "$PLIST_PATH"
    info "Service started via launchd (runs at boot, no login required)."

elif command -v systemctl &>/dev/null; then
    # ── Remove legacy service if present (from older versions) ──
    if systemctl is-active --quiet "wol-shutdown-agent" 2>/dev/null; then
        warn "Removing legacy service 'wol-shutdown-agent' from older version..."
        sudo systemctl stop "wol-shutdown-agent" 2>/dev/null || true
        sudo systemctl disable "wol-shutdown-agent" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/wol-shutdown-agent.service"
        sudo systemctl daemon-reload
    fi

    # ── Linux with systemd ──
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    info "Installing systemd service at $SERVICE_FILE..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Network PC Manager Shutdown Agent
After=network.target

[Service]
Type=simple
Environment=NETWORK_PC_MANAGER_AGENT_PASSPHRASE=${PASSPHRASE}
ExecStart=${PYTHON3_PATH} ${AGENT_SCRIPT} --port ${PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl restart "$SERVICE_NAME"
    info "Service started via systemd (runs at boot, no login required)."

else
    # ── Fallback: cron @reboot ──
    warn "No systemd or launchd found. Falling back to cron."
    CRON_CMD="@reboot NETWORK_PC_MANAGER_AGENT_PASSPHRASE='${PASSPHRASE}' ${PYTHON3_PATH} ${AGENT_SCRIPT} --port ${PORT}"
    if crontab -l 2>/dev/null | grep -qF "shutdown_agent.py"; then
        warn "Cron entry already exists – replacing."
        crontab -l 2>/dev/null | grep -vF "shutdown_agent.py" | { cat; echo "$CRON_CMD"; } | crontab -
    else
        (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
    fi
    info "Cron entry added. Starting agent now..."
    NETWORK_PC_MANAGER_AGENT_PASSPHRASE="$PASSPHRASE" nohup "$PYTHON3_PATH" "$AGENT_SCRIPT" --port "$PORT" &>/var/log/network-pc-manager-agent.log &
    info "Agent started (PID: $!)."
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo
info "Setup complete!"
echo
echo -e "  Agent running on port ${CYAN}${PORT}${NC}"
echo -e "  Passphrase: ${CYAN}(as configured)${NC}"
echo
echo "  Test with:"
echo "    curl -s http://localhost:${PORT}/health"
echo
echo "  Enter this passphrase in the network-pc-manager web UI to shut down this machine."
echo
