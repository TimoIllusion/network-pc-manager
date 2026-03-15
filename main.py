import json
import os
import socket
import urllib.error
import urllib.request

from flask import Flask, request, render_template, jsonify
from wakeonlan import send_magic_packet

from registry import merge_scan
from scan import scan_network

DEFAULT_AGENT_PORT = int(os.environ.get("NETWORK_PC_MANAGER_AGENT_PORT", "9876"))

app = Flask(__name__)


@app.route("/")
def index():
    devices = merge_scan(scan_network())
    return render_template(
        "index.html",
        devices=devices,
        default_agent_port=DEFAULT_AGENT_PORT,
    )


@app.route("/scan")
def scan():
    """Re-scan the network and return the device list as JSON."""
    return jsonify(merge_scan(scan_network()))


@app.route("/wake", methods=["GET"])
def wake():
    mac_address = request.args.get("mac", "")
    if not mac_address:
        return "MAC address is required", 400
    send_magic_packet(mac_address)
    return f"Wake-on-LAN packet sent to {mac_address}", 200


@app.route("/shutdown", methods=["GET"])
def shutdown():
    """Send shutdown request to the remote shutdown agent via HTTP API."""
    ip_address = request.args.get("ip", "")
    port = request.args.get("port", str(DEFAULT_AGENT_PORT))
    passphrase = request.args.get("passphrase", "")

    if not ip_address:
        return "IP address is required", 400
    if not passphrase:
        return "Passphrase is required", 400

    url = f"http://{ip_address}:{port}/shutdown"
    headers = {
        "Authorization": f"Bearer {passphrase}",
        "Content-Type": "application/json",
    }

    try:
        req = urllib.request.Request(url, data=b"{}", headers=headers, method="POST")
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


@app.route("/check-ssh", methods=["GET"])
def check_ssh():
    """Check if SSH (port 22) is reachable on a target machine."""
    ip_address = request.args.get("ip", "")
    port = int(request.args.get("port", "22"))

    if not ip_address:
        return jsonify({"ssh_available": False, "error": "IP address is required"}), 400

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        result = sock.connect_ex((ip_address, port))
        sock.close()
        return jsonify({"ssh_available": result == 0}), 200
    except Exception as e:
        return jsonify({"ssh_available": False, "error": str(e)}), 200


@app.route("/setup-packages", methods=["GET"])
def get_setup_packages():
    """Return the configured setup package list."""
    pkg_file = os.path.join(os.path.dirname(__file__), "setup_packages.json")
    try:
        with open(pkg_file, encoding="utf-8") as f:
            return jsonify(json.load(f)), 200
    except FileNotFoundError:
        return jsonify({"packages": []}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=1337)
