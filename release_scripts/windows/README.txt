Network PC Manager - Shutdown Agent
====================================

This is the standalone shutdown agent for Network PC Manager.
No Python installation required - everything is bundled.

Quick Start
-----------
1. Right-click "install.bat" and select "Run as administrator"
   IMPORTANT: Must be run as Administrator. The script will NOT auto-elevate.
   If you forget, you will get a clear error message telling you what to do.
2. Enter a passphrase (min 8 characters) when prompted
3. Enter a port number or press Enter for the default (9876)
4. Done! The agent is running and will auto-start at system startup (no login required).

Test it:
    Open a browser and go to: http://localhost:9876/health

How It Works
------------
install.bat is a thin launcher that runs install.ps1 (PowerShell).
All logic is in the .ps1 file, which is easier to read and debug.

Troubleshooting
---------------
A log file is written next to install.bat in the same folder:
    install.log

If the installer fails, open that file for step-by-step details.
Common issues:
- "Not running as administrator" -> Right-click the .bat, choose "Run as administrator"
- "shutdown_agent.exe not found"  -> Make sure install.bat, install.ps1, and shutdown_agent.exe
                                     are all in the same folder

What Gets Installed
-------------------
- Executable:    C:\Program Files\NetworkPCManager\shutdown_agent.exe
- Scheduled Task: "NetworkPCManager-ShutdownAgent" (runs at system startup as SYSTEM)
- Firewall Rule:  "NetworkPCManager-ShutdownAgent" (allows inbound TCP on chosen port)
- Environment Var: NETWORK_PC_MANAGER_AGENT_PASSPHRASE (system-level)

Uninstall
---------
Right-click "uninstall.bat" and select "Run as administrator".
This removes everything cleanly (task, firewall rule, env var, files).

More Info
---------
https://github.com/TimoIllusion/network-pc-manager
