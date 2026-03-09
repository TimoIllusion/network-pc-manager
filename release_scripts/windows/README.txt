Network PC Manager - Shutdown Agent
====================================

This is the standalone shutdown agent for Network PC Manager.
No Python installation required - everything is bundled.

Quick Start
-----------
1. Right-click "install.bat" and select "Run as administrator"
   (IMPORTANT: must be run as Administrator - the script will not auto-elevate)
2. Enter a passphrase (min 8 characters) when prompted
3. Enter a port number or press Enter for the default (9876)
4. Done! The agent is running and will auto-start at system startup (no login required).

Test it:
    Open a browser and go to: http://localhost:9876/health

Troubleshooting
---------------
A log file is written to:
    %TEMP%\NetworkPCManager_install.log

If the installer fails, check that file for detailed error output.
Common issues:
- "Not running as administrator" -> Right-click the .bat and choose "Run as administrator"
- "shutdown_agent.exe not found"  -> Make sure install.bat and shutdown_agent.exe are in the same folder

What Gets Installed
-------------------
- Executable:    C:\Program Files\NetworkPCManager\shutdown_agent.exe
- Scheduled Task: "NetworkPCManager-ShutdownAgent" (runs at system startup)
- Firewall Rule:  "NetworkPCManager-ShutdownAgent" (allows inbound TCP)
- Environment Var: NETWORK_PC_MANAGER_AGENT_PASSPHRASE (system-level)

Uninstall
---------
Right-click "uninstall.bat" and select "Run as administrator".
This removes everything cleanly.

More Info
---------
https://github.com/TimoIllusion/network-pc-manager
