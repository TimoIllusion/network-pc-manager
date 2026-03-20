"""Manage a local Ollama instance for LLM inference on the local network."""

import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "llm_config.json")
DEFAULT_CONFIG = {
    "model": "llama3.2:3b",
    "ollama_host": "127.0.0.1",
    "ollama_port": 11434,
}


def load_config():
    """Load LLM config from disk, returning defaults if missing."""
    if os.path.isfile(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            cfg = json.load(f)
        # Merge with defaults for any missing keys
        for k, v in DEFAULT_CONFIG.items():
            cfg.setdefault(k, v)
        return cfg
    return dict(DEFAULT_CONFIG)


def save_config(cfg):
    """Persist LLM config to disk."""
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


def _ollama_api_url(cfg=None):
    cfg = cfg or load_config()
    return f"http://{cfg['ollama_host']}:{cfg['ollama_port']}"


def get_status():
    """Check if Ollama is reachable and return running model info."""
    cfg = load_config()
    base = _ollama_api_url(cfg)
    result = {
        "running": False,
        "model": cfg["model"],
        "ollama_host": cfg["ollama_host"],
        "ollama_port": cfg["ollama_port"],
        "loaded_models": [],
    }

    try:
        req = urllib.request.Request(f"{base}/api/ps", method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            result["running"] = True
            result["loaded_models"] = [
                m.get("name", "") for m in body.get("models", [])
            ]
    except Exception:
        pass

    return result


def start_ollama():
    """Start 'ollama serve' as a background process.

    Sets OLLAMA_HOST=0.0.0.0 so the API is accessible on the local network.
    """
    if not shutil.which("ollama"):
        return False, "ollama not found in PATH. Install Ollama first."

    # Check if already running
    status = get_status()
    if status["running"]:
        return True, "Ollama is already running."

    env = os.environ.copy()
    env["OLLAMA_HOST"] = "0.0.0.0"

    try:
        subprocess.Popen(
            ["ollama", "serve"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True, "Ollama serve started."
    except Exception as e:
        return False, f"Failed to start Ollama: {e}"


def stop_ollama():
    """Stop any running Ollama process."""
    try:
        subprocess.run(
            ["pkill", "-f", "ollama serve"],
            capture_output=True,
            timeout=10,
        )
        return True, "Ollama stopped."
    except FileNotFoundError:
        # Windows fallback
        try:
            subprocess.run(
                ["taskkill", "/F", "/IM", "ollama.exe"],
                capture_output=True,
                timeout=10,
            )
            return True, "Ollama stopped."
        except Exception as e:
            return False, f"Failed to stop Ollama: {e}"
    except Exception as e:
        return False, f"Failed to stop Ollama: {e}"


def pull_model(model=None):
    """Pull (download) a model via Ollama API."""
    cfg = load_config()
    model = model or cfg["model"]
    base = _ollama_api_url(cfg)

    try:
        data = json.dumps({"name": model, "stream": False}).encode("utf-8")
        req = urllib.request.Request(
            f"{base}/api/pull",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=600) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            status_msg = body.get("status", "success")
            return True, f"Model '{model}' pull: {status_msg}"
    except urllib.error.HTTPError as e:
        try:
            detail = json.loads(e.read().decode("utf-8")).get("error", str(e))
        except Exception:
            detail = str(e)
        return False, f"Pull failed: {detail}"
    except Exception as e:
        return False, f"Pull failed: {e}"


def ensure_firewall(port=11434):
    """Add a firewall rule for the Ollama port (Linux only, best-effort)."""
    # Try iptables
    try:
        # Check if rule already exists
        result = subprocess.run(
            ["iptables", "-C", "INPUT", "-p", "tcp", "--dport", str(port), "-j", "ACCEPT"],
            capture_output=True,
            timeout=5,
        )
        if result.returncode == 0:
            return True, f"Firewall rule for port {port} already exists."

        subprocess.run(
            ["iptables", "-I", "INPUT", "-p", "tcp", "--dport", str(port), "-j", "ACCEPT"],
            capture_output=True,
            check=True,
            timeout=5,
        )
        return True, f"Firewall rule added for port {port}."
    except FileNotFoundError:
        pass
    except subprocess.CalledProcessError:
        pass

    # Try ufw
    try:
        subprocess.run(
            ["ufw", "allow", str(port) + "/tcp"],
            capture_output=True,
            check=True,
            timeout=10,
        )
        return True, f"UFW rule added for port {port}."
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    return False, f"Could not add firewall rule for port {port}. You may need to do it manually."
