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
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

from version import __version__

DEFAULT_PORT = 9876
SHUTDOWN_DELAY_SECONDS = 3


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


def get_shutdown_command(delay_minutes=0):
    """Return the appropriate shutdown command for the current OS."""
    system = platform.system().lower()
    if system == "windows":
        delay_seconds = delay_minutes * 60 if delay_minutes > 0 else SHUTDOWN_DELAY_SECONDS
        return ["shutdown", "/s", "/t", str(delay_seconds)]
    else:  # Linux and macOS
        delay_str = f"+{delay_minutes}" if delay_minutes > 0 else "+0"
        return ["sudo", "shutdown", "-h", delay_str]


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
            delay_minutes = 0
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length:
                try:
                    body = json.loads(self.rfile.read(content_length).decode("utf-8"))
                    delay_minutes = max(0, int(body.get("delay_minutes", 0)))
                except Exception:
                    pass
            cmd = get_shutdown_command(delay_minutes)
            system_name = platform.system()
            hostname = platform.node()
            if delay_minutes > 0:
                hours, mins = divmod(delay_minutes, 60)
                delay_label = f"{hours}h {mins}m" if hours else f"{mins}m"
                message = f"Shutdown scheduled in {delay_label} on {hostname} ({system_name})"
            else:
                message = f"Shutdown initiated on {hostname} ({system_name})"
            self._send_json(
                200,
                {
                    "status": "accepted",
                    "message": message,
                    "command": " ".join(cmd),
                    "delay_minutes": delay_minutes,
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
    logger.info("  Endpoints: GET /health, POST /shutdown, POST /restart")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down agent...")
        server.server_close()


if __name__ == "__main__":
    main()
