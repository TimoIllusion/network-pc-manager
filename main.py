import json
import logging
import logging.handlers
import os
import urllib.error
import urllib.request

from flask import Flask, request, render_template, jsonify
from wakeonlan import send_magic_packet

from registry import merge_scan, load_registry, save_registry
from scan import scan_network

DEFAULT_AGENT_PORT = int(os.environ.get("NETWORK_PC_MANAGER_AGENT_PORT", "9876"))

# ── Logging ──────────────────────────────────────────────────────────────────
LOG_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "network-pc-manager.log"
)

logger = logging.getLogger("network-pc-manager")
logger.setLevel(logging.INFO)

_fmt = logging.Formatter("[%(asctime)s] %(levelname)s  %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

_fh = logging.handlers.RotatingFileHandler(
    LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
)
_fh.setFormatter(_fmt)
logger.addHandler(_fh)

_sh = logging.StreamHandler()
_sh.setFormatter(_fmt)
logger.addHandler(_sh)

app = Flask(__name__)


@app.route("/")
def index():
    logger.info("Scanning network for devices...")
    devices = merge_scan(scan_network())
    logger.info("Found %d device(s)", len(devices))
    return render_template(
        "index.html",
        devices=devices,
        default_agent_port=DEFAULT_AGENT_PORT,
    )


@app.route("/scan")
def scan():
    """Re-scan the network and return the device list as JSON."""
    logger.info("Manual network re-scan triggered")
    return jsonify(merge_scan(scan_network()))


@app.route("/wake", methods=["GET"])
def wake():
    mac_address = request.args.get("mac", "")
    if not mac_address:
        return "MAC address is required", 400
    send_magic_packet(mac_address)
    logger.info("Wake-on-LAN packet sent to %s", mac_address)
    return f"Wake-on-LAN packet sent to {mac_address}", 200


@app.route("/shutdown", methods=["GET"])
def shutdown():
    """Send shutdown request to the remote shutdown agent via HTTP API."""
    ip_address = request.args.get("ip", "")
    port = request.args.get("port", str(DEFAULT_AGENT_PORT))
    passphrase = request.args.get("passphrase", "")
    try:
        delay_minutes = max(0, int(request.args.get("delay_minutes", "0")))
    except ValueError:
        delay_minutes = 0

    if not ip_address:
        return "IP address is required", 400
    if not passphrase:
        return "Passphrase is required", 400

    url = f"http://{ip_address}:{port}/shutdown"
    headers = {
        "Authorization": f"Bearer {passphrase}",
        "Content-Type": "application/json",
    }
    payload = json.dumps({"delay_minutes": delay_minutes}).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            msg = body.get("message", "Shutdown accepted")
            return f"Shutdown: {msg}", 200
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8"))
            detail = body.get("error", str(e))
        except Exception:
            detail = str(e)
        return f"Shutdown failed on {ip_address}: {detail}", e.code
    except Exception as e:
        logger.error("Could not reach shutdown agent on %s:%s: %s", ip_address, port, e)
        return f"Could not reach shutdown agent on {ip_address}:{port}: {e}", 500


@app.route("/restart", methods=["GET"])
def restart():
    """Send restart request to the remote shutdown agent via HTTP API."""
    ip_address = request.args.get("ip", "")
    port = request.args.get("port", str(DEFAULT_AGENT_PORT))
    passphrase = request.args.get("passphrase", "")

    if not ip_address:
        return "IP address is required", 400
    if not passphrase:
        return "Passphrase is required", 400

    url = f"http://{ip_address}:{port}/restart"
    headers = {
        "Authorization": f"Bearer {passphrase}",
        "Content-Type": "application/json",
    }

    try:
        req = urllib.request.Request(url, data=b"{}", headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            msg = body.get("message", "Restart accepted")
            return f"Restart: {msg}", 200
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8"))
            detail = body.get("error", str(e))
        except Exception:
            detail = str(e)
        return f"Restart failed on {ip_address}: {detail}", e.code
    except Exception as e:
        return f"Could not reach shutdown agent on {ip_address}:{port}: {e}", 500


@app.route("/rename", methods=["POST"])
def rename():
    """Set or clear the custom name for a registry entry."""
    data = request.get_json(silent=True) or {}
    mac = (data.get("mac") or "").strip().upper()
    custom_name = (data.get("custom_name") or "").strip()
    if not mac:
        return "MAC address is required", 400
    registry = load_registry()
    if mac not in registry:
        return f"Device {mac} not found in registry", 404
    registry[mac]["custom_name"] = custom_name
    save_registry(registry)
    return jsonify({"ok": True})


@app.route("/health-check", methods=["GET"])
def health_check():
    """Check if a remote shutdown agent is reachable."""
    ip_address = request.args.get("ip", "")
    port = request.args.get("port", str(DEFAULT_AGENT_PORT))

    if not ip_address:
        return jsonify({"status": "error", "error": "IP address is required"}), 400

    url = f"http://{ip_address}:{port}/health"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return jsonify(body), 200
    except Exception as e:
        return jsonify({"status": "unreachable", "error": str(e)}), 502


if __name__ == "__main__":
    logger.info("Starting Network PC Manager on port 1337")
    app.run(host="0.0.0.0", port=1337)
