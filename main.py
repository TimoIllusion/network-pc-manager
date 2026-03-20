import json
import os
import urllib.error
import urllib.request

from flask import Flask, request, render_template, jsonify
from wakeonlan import send_magic_packet

from llm_manager import (
    load_config as load_llm_config,
    save_config as save_llm_config,
    get_status as get_llm_status,
    start_ollama,
    stop_ollama,
    pull_model,
    unload_model,
    ensure_firewall,
)
from registry import merge_scan, load_registry, save_registry
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


# ── LLM / Ollama management ──────────────────────────────────────────────────


@app.route("/llm/status", methods=["GET"])
def llm_status():
    """Return Ollama status and current config."""
    return jsonify(get_llm_status())


@app.route("/llm/config", methods=["GET"])
def llm_config_get():
    """Return current LLM configuration."""
    return jsonify(load_llm_config())


@app.route("/llm/config", methods=["POST"])
def llm_config_set():
    """Update LLM configuration (model, ollama_host, ollama_port)."""
    data = request.get_json(silent=True) or {}
    cfg = load_llm_config()
    if "model" in data:
        cfg["model"] = str(data["model"]).strip()
    if "ollama_host" in data:
        cfg["ollama_host"] = str(data["ollama_host"]).strip()
    if "ollama_port" in data:
        cfg["ollama_port"] = int(data["ollama_port"])
    save_llm_config(cfg)
    return jsonify(cfg)


@app.route("/llm/start", methods=["POST"])
def llm_start():
    """Start the local Ollama serve process."""
    ok, msg = start_ollama()
    # Best-effort firewall rule
    cfg = load_llm_config()
    fw_ok, fw_msg = ensure_firewall(cfg["ollama_port"])
    return jsonify({"ok": ok, "message": msg, "firewall": fw_msg}), 200 if ok else 500


@app.route("/llm/stop", methods=["POST"])
def llm_stop():
    """Stop the local Ollama serve process."""
    ok, msg = stop_ollama()
    return jsonify({"ok": ok, "message": msg}), 200 if ok else 500


@app.route("/llm/pull", methods=["POST"])
def llm_pull():
    """Pull (download) the configured model."""
    data = request.get_json(silent=True) or {}
    model = data.get("model") or None
    ok, msg = pull_model(model)
    return jsonify({"ok": ok, "message": msg}), 200 if ok else 500


@app.route("/llm/unload", methods=["POST"])
def llm_unload():
    """Unload a model from memory (free GPU/RAM)."""
    data = request.get_json(silent=True) or {}
    model = data.get("model") or None
    ok, msg = unload_model(model)
    return jsonify({"ok": ok, "message": msg}), 200 if ok else 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=1337)
