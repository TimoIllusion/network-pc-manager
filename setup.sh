#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.env"
SERVICE_NAME="wol-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ─── 1. System dependencies ───────────────────────────────────────────────────
info "Checking system dependencies..."

if ! command -v python3 &>/dev/null; then
    info "python3 not found – installing via apt..."
    sudo apt-get update -qq
    sudo apt-get install -y python3
fi

if ! python3 -m venv --help &>/dev/null 2>&1; then
    info "python3-venv not found – installing..."
    sudo apt-get install -y python3-venv
fi

if ! command -v pip3 &>/dev/null; then
    info "pip3 not found – installing..."
    sudo apt-get install -y python3-pip
fi

PYTHON_VERSION=$(python3 --version)
info "Using $PYTHON_VERSION"

# ─── 2. Virtual environment ────────────────────────────────────────────────────
if [ -d "$VENV_DIR" ]; then
    warn "Virtual environment already exists at $VENV_DIR – skipping creation."
else
    info "Creating virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

info "Activating virtual environment..."
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# ─── 3. Python dependencies ────────────────────────────────────────────────────
info "Installing Python dependencies from requirements.txt..."
pip install --quiet --upgrade pip
pip install --quiet -r "$SCRIPT_DIR/requirements.txt"
info "Dependencies installed successfully."

# ─── 4. systemd service (runs as root for ARP scanning) ──────────────────────
info "Setting up systemd service..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=WOL Proxy – Wake-on-LAN & Remote Shutdown
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python $SCRIPT_DIR/main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"
info "Service started and enabled on boot."

# ─── Done ─────────────────────────────────────────────────────────────────────
# Wait briefly for the service to come up, then show status
sleep 1
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    STATUS="${GREEN}running${NC}"
else
    STATUS="${RED}not running (check: sudo journalctl -u $SERVICE_NAME)${NC}"
fi

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
LOCAL_IP="${LOCAL_IP:-<this-host-ip>}"

echo
info "Setup complete! Service is ${STATUS}"
echo
echo "  Web UI:  http://${LOCAL_IP}:1337"
echo
echo "  Manage:  sudo systemctl {start|stop|restart|status} $SERVICE_NAME"
echo "  Logs:    sudo journalctl -u $SERVICE_NAME -f"
echo
