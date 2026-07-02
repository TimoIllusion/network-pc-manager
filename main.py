import datetime
import json
import logging
import logging.handlers
import os
import shutil
import urllib.error
import urllib.request

from flask import Flask, request, render_template, jsonify
from wakeonlan import send_magic_packet

from registry import merge_scan, load_registry, save_registry, bump_use_count
from scan import scan_network
from settings import load_settings, save_settings
from sync_profiles import (
    load_profiles, save_profiles, get_profile,
    add_profile, update_profile, delete_profile,
)

DEFAULT_AGENT_PORT = int(os.environ.get("NETWORK_PC_MANAGER_AGENT_PORT", "9876"))
SAVES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "saves")
DEFAULT_SAVEGAME_PATH = r"C:\Users\Timo\AppData\Roaming\Road to Vostok"

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
        last_selected=load_settings().get("last_selected_mac", ""),
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
    bump_use_count(mac_address.strip().upper())
    logger.info("Wake-on-LAN packet sent to %s", mac_address)
    return f"Wake-on-LAN packet sent to {mac_address}", 200


def _bump_usage(mac: str, ip_address: str) -> None:
    """Count a device action; resolve the MAC from the registry by IP if absent."""
    if not mac:
        registry = load_registry()
        mac = next((m for m, d in registry.items() if d.get("ip") == ip_address), "")
    if mac:
        bump_use_count(mac)


@app.route("/shutdown", methods=["GET"])
def shutdown():
    """Send shutdown request to the remote shutdown agent via HTTP API."""
    ip_address = request.args.get("ip", "")
    port = request.args.get("port", str(DEFAULT_AGENT_PORT))
    passphrase = request.args.get("passphrase", "")
    mac = request.args.get("mac", "").strip().upper()
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
            _bump_usage(mac, ip_address)
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
    mac = request.args.get("mac", "").strip().upper()

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
            _bump_usage(mac, ip_address)
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


@app.route("/pin", methods=["POST"])
def pin():
    """Set or clear the pinned flag for a registry entry."""
    data = request.get_json(silent=True) or {}
    mac = (data.get("mac") or "").strip().upper()
    pinned = bool(data.get("pinned"))
    if not mac:
        return "MAC address is required", 400
    registry = load_registry()
    if mac not in registry:
        return f"Device {mac} not found in registry", 404
    registry[mac]["pinned"] = pinned
    save_registry(registry)
    return jsonify({"ok": True, "pinned": pinned})


@app.route("/select", methods=["POST"])
def select_device():
    """Remember the last selected device so the UI can restore it on load."""
    data = request.get_json(silent=True) or {}
    mac = (data.get("mac") or "").strip().upper()
    if not mac:
        return "MAC address is required", 400
    settings = load_settings()
    settings["last_selected_mac"] = mac
    save_settings(settings)
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


# ── Save Game Sync ──────────────────────────────────────────────────────────


def _get_save_dir(profile_id: str) -> str:
    return os.path.join(SAVES_DIR, profile_id)


def _get_history_dir(profile_id: str) -> str:
    return os.path.join(SAVES_DIR, profile_id, "history")


def _read_meta(profile_id: str) -> dict | None:
    meta_path = os.path.join(_get_save_dir(profile_id), "meta.json")
    if not os.path.exists(meta_path):
        return None
    with open(meta_path) as f:
        return json.load(f)


def _write_meta(profile_id: str, meta: dict) -> None:
    save_dir = _get_save_dir(profile_id)
    os.makedirs(save_dir, exist_ok=True)
    with open(os.path.join(save_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)


def _list_versions(profile_id: str) -> list[dict]:
    """List all saved versions (current + history) for a profile."""
    versions = []
    # Current version
    current_path = os.path.join(_get_save_dir(profile_id), "data.tar.gz")
    meta = _read_meta(profile_id)
    if meta and os.path.exists(current_path):
        versions.append({
            "id": "current",
            "timestamp": meta.get("timestamp", ""),
            "source_device": meta.get("source_device", ""),
            "source_mac": meta.get("source_mac", ""),
            "size": os.path.getsize(current_path),
            "is_current": True,
        })
    # History versions
    history_dir = _get_history_dir(profile_id)
    if os.path.isdir(history_dir):
        for fname in sorted(os.listdir(history_dir), reverse=True):
            if not fname.endswith(".tar.gz"):
                continue
            version_id = fname[:-7]  # strip .tar.gz
            meta_file = os.path.join(history_dir, version_id + ".json")
            vmeta = {}
            if os.path.exists(meta_file):
                with open(meta_file) as f:
                    vmeta = json.load(f)
            versions.append({
                "id": version_id,
                "timestamp": vmeta.get("timestamp", version_id),
                "source_device": vmeta.get("source_device", ""),
                "source_mac": vmeta.get("source_mac", ""),
                "size": os.path.getsize(os.path.join(history_dir, fname)),
                "is_current": False,
            })
    return versions


@app.route("/sync-profiles", methods=["GET"])
def list_sync_profiles():
    """Return all sync profiles with their save metadata."""
    profiles = load_profiles()
    result = []
    for p in profiles:
        meta = _read_meta(p["id"])
        result.append({
            **p,
            "has_save": meta is not None,
            "last_upload": meta.get("timestamp") if meta else None,
            "last_source": meta.get("source_device") if meta else None,
            "save_size": meta.get("size") if meta else None,
        })
    return jsonify(result)


@app.route("/sync-profiles", methods=["POST"])
def create_sync_profile():
    """Create or update a sync profile."""
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    # Paths are currently fixed to DEFAULT_SAVEGAME_PATH, so we don't require
    # per-device configuration. (We still persist paths for forward-compat.)
    paths = data.get("paths") or {}
    profile_id = data.get("id")

    if not name:
        return jsonify({"error": "Name is required"}), 400

    if profile_id:
        updated = update_profile(profile_id, name=name, paths=paths)
        if updated:
            return jsonify(updated)
        return jsonify({"error": "Profile not found"}), 404

    profile = add_profile(name, paths)
    return jsonify(profile), 201


@app.route("/sync-profiles/<profile_id>", methods=["DELETE"])
def delete_sync_profile(profile_id):
    """Delete a sync profile and its stored saves."""
    if not delete_profile(profile_id):
        return jsonify({"error": "Profile not found"}), 404
    # Clean up stored saves
    save_dir = _get_save_dir(profile_id)
    if os.path.isdir(save_dir):
        shutil.rmtree(save_dir)
    return jsonify({"ok": True})


@app.route("/sync/versions", methods=["GET"])
def sync_versions():
    """List all saved versions for a profile."""
    profile_id = request.args.get("profile_id", "")
    if not profile_id:
        return jsonify({"error": "profile_id is required"}), 400
    profile = get_profile(profile_id)
    if not profile:
        return jsonify({"error": "Profile not found"}), 404
    return jsonify(_list_versions(profile_id))


@app.route("/sync/upload", methods=["POST"])
def sync_upload():
    """Upload saves from a PC agent to the server's central storage."""
    data = request.get_json(silent=True) or {}
    profile_id = data.get("profile_id", "")
    source_mac = (data.get("source_mac") or "").strip().upper()
    passphrase = data.get("passphrase", "")
    port = data.get("port", str(DEFAULT_AGENT_PORT))

    if not profile_id or not source_mac or not passphrase:
        return jsonify({"error": "profile_id, source_mac, and passphrase are required"}), 400

    profile = get_profile(profile_id)
    if not profile:
        return jsonify({"error": "Profile not found"}), 404

    source_path = profile.get("paths", {}).get(source_mac) or DEFAULT_SAVEGAME_PATH

    # Look up device IP
    registry = load_registry()
    device = registry.get(source_mac)
    if not device or not device.get("ip"):
        return jsonify({"error": f"Device {source_mac} not found or offline"}), 404

    ip = device["ip"]
    device_name = device.get("custom_name") or device.get("name", ip)

    # Download tar.gz from agent
    url = f"http://{ip}:{port}/files/download"
    headers = {
        "Authorization": f"Bearer {passphrase}",
        "Content-Type": "application/json",
    }
    payload = json.dumps({"path": source_path}).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=60) as resp:
            tar_data = resp.read()
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8"))
            detail = body.get("error", str(e))
        except Exception:
            detail = str(e)
        return jsonify({"error": f"Agent download failed: {detail}"}), e.code
    except Exception as e:
        logger.error("Could not download from agent %s:%s: %s", ip, port, e)
        return jsonify({"error": f"Could not reach agent: {e}"}), 502

    # Move current save to history (if exists)
    save_dir = _get_save_dir(profile_id)
    current_path = os.path.join(save_dir, "data.tar.gz")
    if os.path.exists(current_path):
        history_dir = _get_history_dir(profile_id)
        os.makedirs(history_dir, exist_ok=True)
        old_meta = _read_meta(profile_id)
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        shutil.move(current_path, os.path.join(history_dir, f"{ts}.tar.gz"))
        if old_meta:
            with open(os.path.join(history_dir, f"{ts}.json"), "w") as f:
                json.dump(old_meta, f, indent=2)

    # Save new version
    os.makedirs(save_dir, exist_ok=True)
    with open(current_path, "wb") as f:
        f.write(tar_data)

    now = datetime.datetime.now(tz=datetime.timezone.utc).isoformat()
    _write_meta(profile_id, {
        "timestamp": now,
        "source_mac": source_mac,
        "source_device": device_name,
        "size": len(tar_data),
        "source_path": source_path,
    })

    logger.info("Sync upload: %s from %s (%s), %d bytes", profile_id, device_name, source_mac, len(tar_data))
    return jsonify({
        "status": "ok",
        "message": f"Saves uploaded from {device_name}",
        "size": len(tar_data),
        "timestamp": now,
    })


@app.route("/sync/download", methods=["POST"])
def sync_download():
    """Download saves from server storage to a PC agent."""
    data = request.get_json(silent=True) or {}
    profile_id = data.get("profile_id", "")
    dest_mac = (data.get("dest_mac") or "").strip().upper()
    passphrase = data.get("passphrase", "")
    port = data.get("port", str(DEFAULT_AGENT_PORT))
    version_id = data.get("version_id", "current")

    if not profile_id or not dest_mac or not passphrase:
        return jsonify({"error": "profile_id, dest_mac, and passphrase are required"}), 400

    profile = get_profile(profile_id)
    if not profile:
        return jsonify({"error": "Profile not found"}), 404

    dest_path = profile.get("paths", {}).get(dest_mac) or DEFAULT_SAVEGAME_PATH

    # Find the tar.gz to send
    if version_id == "current":
        tar_path = os.path.join(_get_save_dir(profile_id), "data.tar.gz")
    else:
        tar_path = os.path.join(_get_history_dir(profile_id), f"{version_id}.tar.gz")

    if not os.path.exists(tar_path):
        return jsonify({"error": "No save data found for this version"}), 404

    with open(tar_path, "rb") as f:
        tar_data = f.read()

    # Look up device IP
    registry = load_registry()
    device = registry.get(dest_mac)
    if not device or not device.get("ip"):
        return jsonify({"error": f"Device {dest_mac} not found or offline"}), 404

    ip = device["ip"]
    device_name = device.get("custom_name") or device.get("name", ip)

    # Upload tar.gz to agent
    url = f"http://{ip}:{port}/files/upload"
    headers = {
        "Authorization": f"Bearer {passphrase}",
        "Content-Type": "application/gzip",
        "X-Sync-Path": dest_path,
        "Content-Length": str(len(tar_data)),
    }

    try:
        req = urllib.request.Request(url, data=tar_data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8"))
            detail = body.get("error", str(e))
        except Exception:
            detail = str(e)
        return jsonify({"error": f"Agent upload failed: {detail}"}), e.code
    except Exception as e:
        logger.error("Could not upload to agent %s:%s: %s", ip, port, e)
        return jsonify({"error": f"Could not reach agent: {e}"}), 502

    logger.info("Sync download: %s to %s (%s), %d bytes", profile_id, device_name, dest_mac, len(tar_data))
    return jsonify({
        "status": "ok",
        "message": f"Saves downloaded to {device_name}",
        "size": len(tar_data),
    })


if __name__ == "__main__":
    os.makedirs(SAVES_DIR, exist_ok=True)
    logger.info("Starting Network PC Manager on port 1337")
    app.run(host="0.0.0.0", port=1337)
