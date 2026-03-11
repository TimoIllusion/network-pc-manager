#!/usr/bin/env python3
"""
Network PC Manager Shutdown Agent
==================================
A lightweight, cross-platform HTTP server that accepts authenticated
remote shutdown requests. Runs on target machines as an alternative
to SSH-based shutdown.

Zero external dependencies - uses only Python standard library.

Usage:
    python shutdown_agent.py --passphrase "your-secret-phrase"
    python shutdown_agent.py --passphrase "your-secret-phrase" --port 9876
    NETWORK_PC_MANAGER_AGENT_PASSPHRASE="your-secret-phrase" python shutdown_agent.py

The agent listens for POST requests to /shutdown with the header:
    Authorization: Bearer <passphrase>
"""

import argparse
import hashlib
import hmac
import json
import logging
import logging.handlers
import os
import platform
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

from version import __version__

DEFAULT_PORT = 9876
SHUTDOWN_DELAY_SECONDS = 3
GITHUB_REPO = "TimoIllusion/network-pc-manager"


def _fetch_latest_github_release():
    """Query GitHub API and return (tag_name, win_x64_download_url_or_None)."""
    url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": "NetworkPCManager-Agent"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    tag = data["tag_name"]
    for asset in data.get("assets", []):
        if "win-x64" in asset["name"] and asset["name"].endswith(".zip"):
            return tag, asset["browser_download_url"]
    return tag, None


def _parse_version(v):
    """Parse 'v0.2.0' or '0.2.0' into a comparable tuple of ints."""
    return tuple(int(x) for x in v.lstrip("v").split("."))


def _start_windows_update(download_url):
    """Write a detached PowerShell updater script and schedule agent exit."""
    install_dir = os.path.dirname(sys.executable)
    task_name = "NetworkPCManager-ShutdownAgent"
    script = (
        "$ErrorActionPreference = 'Stop'\n"
        "Start-Sleep -Seconds 3\n"
        "$zip = \"$env:TEMP\\npm_update.zip\"\n"
        "$dir = \"$env:TEMP\\npm_update\"\n"
        f"Invoke-WebRequest -Uri '{download_url}' -OutFile $zip -UseBasicParsing\n"
        "if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }\n"
        "Expand-Archive -Path $zip -DestinationPath $dir\n"
        "$exe = Get-ChildItem -Path $dir -Filter 'shutdown_agent.exe' -Recurse | Select-Object -First 1\n"
        f"Stop-ScheduledTask -TaskName '{task_name}' -ErrorAction SilentlyContinue\n"
        "Start-Sleep -Seconds 2\n"
        f"Copy-Item $exe.FullName '{install_dir}\\shutdown_agent.exe' -Force\n"
        f"Start-ScheduledTask -TaskName '{task_name}'\n"
        "Remove-Item $zip -ErrorAction SilentlyContinue\n"
        "Remove-Item $dir -Recurse -ErrorAction SilentlyContinue\n"
    )
    script_path = os.path.join(tempfile.gettempdir(), "npm_selfupdate.ps1")
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(script)
    subprocess.Popen(
        ["powershell.exe", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script_path],
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    threading.Timer(2.0, lambda: os._exit(0)).start()


def _start_unix_update():
    """Invoke update_agent.sh from the repo root as a background process."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    update_sh = os.path.join(script_dir, "update_agent.sh")
    if not os.path.isfile(update_sh):
        raise FileNotFoundError(f"update_agent.sh not found at {update_sh}")
    subprocess.Popen(["bash", update_sh], start_new_session=True)


def get_default_log_path():
    """Return a platform-appropriate default log file path."""
    if platform.system().lower() == "windows":
        base = os.environ.get("PROGRAMDATA", r"C:\ProgramData")
        return os.path.join(base, "NetworkPCManager", "shutdown_agent.log")
    return "/var/log/network-pc-manager-agent.log"


def setup_logging(log_file):
    """Configure logging to write to both stderr and a rotating file."""
    logger = logging.getLogger("shutdown_agent")
    logger.setLevel(logging.INFO)

    fmt = logging.Formatter("[%(asctime)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    # File handler with rotation (5 MB max, keep 3 backups)
    log_dir = os.path.dirname(log_file)
    if log_dir:
        try:
            os.makedirs(log_dir, exist_ok=True)
        except OSError:
            pass
    try:
        fh = logging.handlers.RotatingFileHandler(
            log_file, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
        )
        fh.setFormatter(fmt)
        logger.addHandler(fh)
    except OSError as e:
        print(f"WARNING: Could not open log file {log_file!r}: {e}", file=sys.stderr)

    # Always also log to stderr
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    return logger


def get_shutdown_command():
    """Return the appropriate shutdown command for the current OS."""
    system = platform.system().lower()
    if system == "windows":
        return ["shutdown", "/s", "/t", str(SHUTDOWN_DELAY_SECONDS)]
    elif system == "darwin":
        return ["sudo", "shutdown", "-h", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]
    else:  # Linux and others
        return ["sudo", "shutdown", "-h", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]


def get_restart_command():
    """Return the appropriate restart command for the current OS."""
    system = platform.system().lower()
    if system == "windows":
        return ["shutdown", "/r", "/t", str(SHUTDOWN_DELAY_SECONDS)]
    elif system == "darwin":
        return ["sudo", "shutdown", "-r", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]
    else:  # Linux and others
        return ["sudo", "shutdown", "-r", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]


def constant_time_compare(a: str, b: str) -> bool:
    """Compare two strings in constant time to prevent timing attacks."""
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


class ShutdownHandler(BaseHTTPRequestHandler):
    """HTTP request handler for the shutdown agent."""

    passphrase = ""

    def log_message(self, format, *args):
        """Override to route HTTP request logs through the logging module."""
        logging.getLogger("shutdown_agent").info(
            "%s - %s", self.client_address[0], format % args
        )

    def _send_json(self, status_code, data):
        """Send a JSON response."""
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self) -> bool:
        """Validate the Authorization header. Returns True if authorized."""
        auth_header = self.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            self._send_json(401, {"error": "Missing or invalid Authorization header"})
            return False
        token = auth_header[len("Bearer ") :]
        if not constant_time_compare(token, self.passphrase):
            self._send_json(403, {"error": "Invalid passphrase"})
            return False
        return True

    def do_GET(self):
        if self.path == "/health":
            self._send_json(
                200,
                {
                    "status": "ok",
                    "hostname": platform.node(),
                    "system": platform.system(),
                    "version": __version__,
                },
            )
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        if self.path == "/shutdown":
            if not self._check_auth():
                return
            cmd = get_shutdown_command()
            system_name = platform.system()
            hostname = platform.node()
            self._send_json(
                200,
                {
                    "status": "accepted",
                    "message": f"Shutdown initiated on {hostname} ({system_name})",
                    "command": " ".join(cmd),
                    "delay_seconds": SHUTDOWN_DELAY_SECONDS,
                },
            )
            self.log_message("Shutdown accepted - executing: %s", " ".join(cmd))
            try:
                if system_name.lower() == "windows":
                    subprocess.Popen(cmd, creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    subprocess.Popen(cmd)
            except Exception as e:
                self.log_message("Shutdown command failed: %s", str(e))
        elif self.path == "/restart":
            if not self._check_auth():
                return
            cmd = get_restart_command()
            system_name = platform.system()
            hostname = platform.node()
            self._send_json(
                200,
                {
                    "status": "accepted",
                    "message": f"Restart initiated on {hostname} ({system_name})",
                    "command": " ".join(cmd),
                    "delay_seconds": SHUTDOWN_DELAY_SECONDS,
                },
            )
            self.log_message("Restart accepted - executing: %s", " ".join(cmd))
            try:
                if system_name.lower() == "windows":
                    subprocess.Popen(cmd, creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    subprocess.Popen(cmd)
            except Exception as e:
                self.log_message("Restart command failed: %s", str(e))
        elif self.path == "/update":
            if not self._check_auth():
                return
            try:
                tag, download_url = _fetch_latest_github_release()
                latest = _parse_version(tag)
                current = _parse_version(__version__)
                if latest <= current:
                    self._send_json(200, {"status": "up_to_date", "version": __version__})
                    return
                system = platform.system().lower()
                new_version = tag.lstrip("v")
                if system == "windows":
                    if not download_url:
                        self._send_json(500, {"error": "No Windows release asset found on GitHub"})
                        return
                    self._send_json(200, {
                        "status": "update_initiated",
                        "current_version": __version__,
                        "new_version": new_version,
                    })
                    self.log_message("Update to %s initiated (Windows)", tag)
                    _start_windows_update(download_url)
                else:
                    self._send_json(200, {
                        "status": "update_initiated",
                        "current_version": __version__,
                        "new_version": new_version,
                    })
                    self.log_message("Update to %s initiated (Unix)", tag)
                    _start_unix_update()
            except Exception as e:
                self._send_json(500, {"error": f"Update failed: {e}"})
        else:
            self._send_json(404, {"error": "Not found"})


def main():
    parser = argparse.ArgumentParser(
        description="Network PC Manager Shutdown Agent - accepts authenticated remote shutdown requests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --passphrase "my-secret"
  %(prog)s --passphrase "my-secret" --port 9876
  %(prog)s --passphrase "my-secret" --bind 127.0.0.1

Environment variables:
  NETWORK_PC_MANAGER_AGENT_PASSPHRASE   Alternative to --passphrase flag
""",
    )
    parser.add_argument(
        "--passphrase",
        default=os.environ.get("NETWORK_PC_MANAGER_AGENT_PASSPHRASE", ""),
        help="Shared secret for authentication (or set NETWORK_PC_MANAGER_AGENT_PASSPHRASE env var)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("NETWORK_PC_MANAGER_AGENT_PORT", DEFAULT_PORT)),
        help=f"Port to listen on (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--bind",
        default="0.0.0.0",
        help="Address to bind to (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--log-file",
        default=get_default_log_path(),
        help=f"Path to log file (default: {get_default_log_path()})",
    )
    args = parser.parse_args()

    if not args.passphrase:
        parser.error(
            "A passphrase is required. Use --passphrase or set NETWORK_PC_MANAGER_AGENT_PASSPHRASE."
        )

    if len(args.passphrase) < 8:
        print(
            "WARNING: Passphrase is shorter than 8 characters. "
            "Consider using a stronger passphrase.",
            file=sys.stderr,
        )

    logger = setup_logging(args.log_file)

    ShutdownHandler.passphrase = args.passphrase

    server = HTTPServer((args.bind, args.port), ShutdownHandler)
    logger.info("Network PC Manager Shutdown Agent %s starting", __version__)
    logger.info("  Hostname : %s", platform.node())
    logger.info("  System   : %s %s", platform.system(), platform.release())
    logger.info("  Listening: http://%s:%s", args.bind, args.port)
    logger.info("  Log file : %s", args.log_file)
    logger.info("  Endpoints: GET /health, POST /shutdown, POST /restart, POST /update")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down agent...")
        server.server_close()


if __name__ == "__main__":
    main()
