# network-pc-manager

Wake, shut down, restart, and manage computers on your local network — from your browser.

A lightweight Flask web app that runs on a Raspberry Pi (or any Linux box) and provides a mobile-friendly UI for Wake-on-LAN, remote shutdown/restart, save game sync, and automated PC setup.

---

## Features

- **Wake** any machine with one tap (Wake-on-LAN magic packet)
- **Shut down or restart** machines remotely via a small agent — no SSH needed
- **Shutdown timer** — schedule shutdown up to 8 hours in advance
- **Passphrase protection** for all power commands
- **Auto-discovers** all devices on the network via ARP scan
- **Custom device names** — rename devices for easier identification
- **Save game sync** — upload/download save files between PCs through a central server with full version history
- **PC bootstrap** — one-click setup of a new Windows machine (installs packages via winget)
- **Agent auto-update** via included update scripts

---

## How It Works

```
Phone / Browser  ──>  network-pc-manager (Pi)  ──WOL magic packet──>  Target PC (wakes up)
                                                ──HTTP (shutdown/restart/sync)──>  Agent on Target PC
```

Two components:

1. **Server** (`main.py`) — runs on a Raspberry Pi (or similar), serves the web UI, sends WOL packets, and coordinates all commands
2. **Shutdown Agent** (`shutdown_agent.py`) — runs on each target PC, accepts authenticated shutdown, restart, and file sync commands over HTTP (Python stdlib only, no extra dependencies)

---

## Server Setup (Raspberry Pi)

```bash
git clone https://github.com/TimoIllusion/network-pc-manager.git && cd network-pc-manager && bash setup.sh
```

The setup script installs dependencies, creates a venv, registers a systemd service, and starts the server immediately. It will also auto-start on boot.

Open `http://<pi-ip>:1337` on your phone.

### Configuration

Set these as environment variables in the systemd service file at `/etc/systemd/system/network-pc-manager.service` if needed.

| Variable | Description | Default |
|---|---|---|
| `NETWORK_PC_MANAGER_SUBNET` | Subnet to scan (CIDR) | auto-detected |
| `NETWORK_PC_MANAGER_AGENT_PORT` | Default shutdown agent port | `9876` |

---

## Shutdown Agent Setup (Target PCs)

The agent is required for remote **shutdown**, **restart**, and **save game sync**. Waking machines works without it (just enable WOL in BIOS).

### Windows — Standalone Release (Recommended, no Python required)

1. Download the latest `NetworkPCManager-ShutdownAgent-win-x64.zip` from [Releases](https://github.com/TimoIllusion/network-pc-manager/releases)
2. Extract the zip
3. Right-click `install.bat` → **Run as administrator**
4. Enter a passphrase and port when prompted

The installer copies the agent to `C:\Program Files\NetworkPCManager`, creates a scheduled task for auto-start, and adds a firewall rule. To remove it, run `uninstall.bat` as administrator.

### Windows — From Source

1. Install [Python](https://www.python.org/downloads/)
2. Clone or download this repo
3. Run `setup_agent.bat` as Administrator

### Linux / macOS

```bash
git clone https://github.com/TimoIllusion/network-pc-manager.git && cd network-pc-manager && bash setup_agent.sh
```

All setup methods prompt for a passphrase (min 8 characters) and register the agent as a system service that starts on boot.

### Agent Configuration

| Variable | Description |
|---|---|
| `NETWORK_PC_MANAGER_AGENT_PASSPHRASE` | Agent passphrase (overrides interactive prompt) |
| `NETWORK_PC_MANAGER_SYNC_DIRS` | Comma-separated list of directories allowed for file sync |

---

## Key Features in Detail

### Remote Shutdown & Restart

All power commands require a passphrase. A prompt appears in the UI when no passphrase has been entered yet in the current session.

The **shutdown timer** lets you delay shutdown from 30 minutes up to 8 hours.

### Save Game Sync

Save game sync lets you back up and restore save files between machines through the central Pi server.

**Setup:** configure allowed sync directories on the agent via `NETWORK_PC_MANAGER_SYNC_DIRS` (or the `--sync-dirs` flag). On Windows, the Road to Vostok save path (`%APPDATA%\Road to Vostok`) is pre-configured.

**Workflow:**
1. Create a sync profile for a game in the UI
2. **Upload saves** — pulls saves from a selected PC and stores them on the server (with automatic backup)
3. **Download saves** — pushes any stored version to any PC (agent creates a backup before extracting)
4. **Version history** — every upload is retained; restore any previous version at any time

### Device Renaming

Devices discovered by ARP scan can be given custom names. Custom-named devices appear first in lists. Names persist across rescans.

### PC Bootstrap

`bootstrap.ps1` automates setting up a new Windows machine:

- Runs the shutdown agent installer
- Installs a curated set of tools via winget:
  - Chrome, Steam, RustDesk (remote access)
  - HWiNFO, Argus Monitor, CPU-Z, GPU-Z, AIDA64 Extreme, FurMark, OCCT

Run it as Administrator on a fresh machine. Progress is logged to `bootstrap.log`.

---

## Service Management

```bash
# Server (on the Pi)
sudo systemctl {start|stop|restart|status} network-pc-manager
sudo journalctl -u network-pc-manager -f

# Agent (on target Linux machines)
sudo systemctl {start|stop|restart|status} wol-shutdown-agent
sudo journalctl -u wol-shutdown-agent -f
```

---

## HTTP API

### Server endpoints (port 1337)

```bash
# Scan the network for devices
curl http://<pi-ip>:1337/scan

# Wake a machine
curl "http://<pi-ip>:1337/wake?mac=AA:BB:CC:DD:EE:FF"

# Shut down via agent (optional: delay_minutes=30..480)
curl "http://<pi-ip>:1337/shutdown?ip=192.168.1.50&port=9876&passphrase=my-secret&delay_minutes=60"

# Restart via agent
curl "http://<pi-ip>:1337/restart?ip=192.168.1.50&port=9876&passphrase=my-secret"
```

### Agent endpoints (port 9876)

All agent endpoints require `Authorization: Bearer <passphrase>`.

```bash
# Health check (returns hostname, OS, version)
curl -H "Authorization: Bearer my-secret" http://<pc-ip>:9876/health

# Shutdown with optional delay
curl -X POST -H "Authorization: Bearer my-secret" \
  -d '{"delay_minutes": 60}' http://<pc-ip>:9876/shutdown

# Restart
curl -X POST -H "Authorization: Bearer my-secret" http://<pc-ip>:9876/restart
```

---

## Building Release Packages

```bash
pip install pyinstaller
python build_agent.py
```

This produces `dist/NetworkPCManager-ShutdownAgent-win-x64.zip` with the bundled executable, installer, and uninstaller.

Releases are also built automatically by GitHub Actions when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## AI Acknowledgment

This project was developed with the assistance of AI tools from [Anthropic](https://www.anthropic.com/) (Claude) and [OpenAI](https://openai.com/) (ChatGPT).

## License

This project is licensed under the [MIT License](LICENSE).
