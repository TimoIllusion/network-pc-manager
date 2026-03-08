# network-pc-manager

Wake up and shut down computers on your local network from your browser.

A lightweight Flask web app that runs on a Raspberry Pi (or any Linux box) and provides a mobile-friendly UI for Wake-on-LAN and remote shutdown.

- **Auto-discovers** all devices on the network via ARP scan
- **Wake** any machine with a single tap (Wake-on-LAN magic packet)
- **Shut down** machines via a small agent running on the target (no SSH needed)

---

## How It Works

```
Phone / Browser  ──>  network-pc-manager (Pi)  ──WOL magic packet──>  Target PC (wakes up)
                                                ──HTTP shutdown────>  Target PC (shuts down)
```

Two components:
1. **Server** (`main.py`) — runs on a Raspberry Pi (or similar), serves the web UI, sends WOL packets, forwards shutdown requests
2. **Shutdown Agent** (`shutdown_agent.py`) — runs on each target PC, accepts authenticated shutdown commands over HTTP (zero dependencies, Python stdlib only)

---

## Server Setup (Raspberry Pi)

```bash
git clone https://github.com/TimoIllusion/network-pc-manager.git && cd network-pc-manager && bash setup.sh
```

That's it. The setup script installs dependencies, creates a venv, sets up a systemd service, and starts the server immediately. It will also auto-start on boot.

Open `http://<pi-ip>:1337` on your phone.

### Optional configuration

| Environment Variable | Description | Default |
|---|---|---|
| `NETWORK_PC_MANAGER_SUBNET` | Subnet to scan (CIDR) | auto-detected |
| `NETWORK_PC_MANAGER_AGENT_PORT` | Default shutdown agent port | `9876` |

Set these in the systemd service file at `/etc/systemd/system/network-pc-manager.service` if needed.

---

## Shutdown Agent Setup (Target PCs)

The agent is needed only if you want to **shut down** machines remotely. Waking up machines works without it (just enable WOL in BIOS).

### Linux / macOS

```bash
git clone https://github.com/TimoIllusion/network-pc-manager.git && cd network-pc-manager && bash setup_agent.sh
```

### Windows

1. Install [Python](https://www.python.org/downloads/) if not already installed
2. Clone or download this repo
3. Run `setup_agent.bat` as Administrator

Both scripts prompt for a passphrase (min 8 characters) and set up the agent as a system service that starts on boot.

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

```bash
# Scan the network for devices
curl http://<pi-ip>:1337/scan

# Wake a machine
curl "http://<pi-ip>:1337/wake?mac=AA:BB:CC:DD:EE:FF"

# Shut down via agent
curl "http://<pi-ip>:1337/shutdown?ip=192.168.1.50&port=9876&passphrase=my-secret"
```

---

## AI Acknowledgment

This project was developed with the assistance of AI tools from [Anthropic](https://www.anthropic.com/) (Claude) and [OpenAI](https://openai.com/) (ChatGPT).

## License

This project is licensed under the [MIT License](LICENSE).
