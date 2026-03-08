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
import os
import platform
import subprocess
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

DEFAULT_PORT = 9876
SHUTDOWN_DELAY_SECONDS = 3


def get_shutdown_command():
    """Return the appropriate shutdown command for the current OS."""
    system = platform.system().lower()
    if system == "windows":
        return ["shutdown", "/s", "/t", str(SHUTDOWN_DELAY_SECONDS)]
    elif system == "darwin":
        return ["sudo", "shutdown", "-h", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]
    else:  # Linux and others
        return ["sudo", "shutdown", "-h", f"+{max(1, SHUTDOWN_DELAY_SECONDS // 60)}"]


def constant_time_compare(a: str, b: str) -> bool:
    """Compare two strings in constant time to prevent timing attacks."""
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


class ShutdownHandler(BaseHTTPRequestHandler):
    """HTTP request handler for the shutdown agent."""

    passphrase = ""

    def log_message(self, format, *args):
        """Override to add timestamps to log messages."""
        sys.stderr.write(
            f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {self.client_address[0]} - {format % args}\n"
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
                    "version": "1.0.0",
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

    ShutdownHandler.passphrase = args.passphrase

    server = HTTPServer((args.bind, args.port), ShutdownHandler)
    print(f"Network PC Manager Shutdown Agent v1.0.0")
    print(f"  Hostname : {platform.node()}")
    print(f"  System   : {platform.system()} {platform.release()}")
    print(f"  Listening: http://{args.bind}:{args.port}")
    print(f"  Endpoints:")
    print(f"    GET  /health   - Health check (no auth required)")
    print(f"    POST /shutdown - Initiate shutdown (auth required)")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down agent...")
        server.server_close()


if __name__ == "__main__":
    main()
