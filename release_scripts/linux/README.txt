Network PC Manager - Shutdown Agent (Linux)
============================================

This is the standalone shutdown agent for Network PC Manager.
No Python installation required - everything is bundled.

Quick Start
-----------
1. Open a terminal in this folder
2. Run:  sudo bash install.sh
   (The script will re-exec itself as root if you forget sudo.)
3. Enter a passphrase (min 8 characters recommended) when prompted
4. Enter a port number or press Enter for the default (9876)
5. Done! The agent is running and will auto-start at boot.

Test it:
    curl -s http://localhost:9876/health

What Gets Installed
-------------------
- Binary:          /opt/network-pc-manager/shutdown_agent
- systemd service: /etc/systemd/system/network-pc-manager-agent.service
                   (runs at boot as root, no login required)
- Log file:        /var/log/network-pc-manager-agent.log

If systemd is not available, the installer falls back to a cron @reboot entry.

Proxmox Notes
-------------
On Proxmox VE hosts and LXC containers the agent runs as root and does not
need sudo. The agent detects this automatically and calls 'shutdown' directly.
A container can only shut down its own environment; use the agent on the
Proxmox host to shut down the host itself.

Update
------
Run:  sudo bash update.sh
This downloads the latest linux-x64 release from GitHub, replaces the binary,
and restarts the service. Use -force to reinstall the same version:
    sudo bash update.sh -force

Uninstall
---------
Run:  sudo bash uninstall.sh
This stops the service, removes the binary and service file, and optionally
deletes the log file.

More Info
---------
https://github.com/TimoIllusion/network-pc-manager
