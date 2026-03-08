#!/usr/bin/env python3
"""
Build script for the Network PC Manager Shutdown Agent release package.

Creates a standalone zip containing:
  - shutdown_agent.exe  (PyInstaller one-file bundle, no Python needed)
  - install.bat         (interactive installer: passphrase, port, firewall, scheduled task)
  - uninstall.bat       (removes everything cleanly)
  - README.txt          (quick-start instructions)

Usage:
    pip install pyinstaller
    python build_agent.py

Output:
    dist/NetworkPCManager-ShutdownAgent-win-x64.zip
"""

import os
import platform
import shutil
import subprocess
import sys
import zipfile

AGENT_SCRIPT = "shutdown_agent.py"
DIST_DIR = "dist"
BUILD_DIR = "build"
PACKAGE_NAME = "NetworkPCManager-ShutdownAgent"


def run(cmd, **kwargs):
    print(f"  > {' '.join(cmd)}")
    subprocess.check_call(cmd, **kwargs)


def inject_version():
    """Write version.py from the VERSION env var if set, otherwise keep the placeholder."""
    version = os.environ.get("VERSION", "").strip()
    if version:
        with open("version.py", "w") as f:
            f.write(f'__version__ = "{version}"\n')
        print(f"  -> Injected version: {version}")
    else:
        print("  -> No VERSION env var set; using placeholder from version.py")


def build_exe():
    """Use PyInstaller to create a single-file executable."""
    print("[1/3] Building standalone executable with PyInstaller...")
    inject_version()
    run([
        sys.executable, "-m", "PyInstaller",
        "--onefile",
        "--name", "shutdown_agent",
        "--console",
        "--clean",
        "--distpath", os.path.join(DIST_DIR, "exe"),
        "--workpath", os.path.join(BUILD_DIR, "pyinstaller"),
        "--specpath", BUILD_DIR,
        AGENT_SCRIPT,
    ])


def create_zip():
    """Package the exe and helper scripts into a release zip."""
    print("[2/3] Creating release zip...")

    system = platform.system().lower()
    if system == "windows":
        arch = "x64" if platform.machine().endswith("64") else "x86"
        zip_name = f"{PACKAGE_NAME}-win-{arch}.zip"
        exe_name = "shutdown_agent.exe"
    elif system == "linux":
        zip_name = f"{PACKAGE_NAME}-linux-x64.zip"
        exe_name = "shutdown_agent"
    elif system == "darwin":
        zip_name = f"{PACKAGE_NAME}-macos-x64.zip"
        exe_name = "shutdown_agent"
    else:
        zip_name = f"{PACKAGE_NAME}-{system}.zip"
        exe_name = "shutdown_agent"

    zip_path = os.path.join(DIST_DIR, zip_name)
    exe_path = os.path.join(DIST_DIR, "exe", exe_name)

    if not os.path.isfile(exe_path):
        print(f"ERROR: Expected executable not found at {exe_path}")
        sys.exit(1)

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(exe_path, exe_name)

        # Include helper scripts for Windows
        scripts_dir = os.path.join("release_scripts", "windows")
        if os.path.isdir(scripts_dir):
            for fname in os.listdir(scripts_dir):
                fpath = os.path.join(scripts_dir, fname)
                if os.path.isfile(fpath):
                    zf.write(fpath, fname)

    print(f"  -> {zip_path}  ({os.path.getsize(zip_path) / 1024 / 1024:.1f} MB)")
    return zip_path


def cleanup():
    """Remove intermediate build artefacts."""
    print("[3/3] Cleaning up build artefacts...")
    for d in [BUILD_DIR, os.path.join(DIST_DIR, "exe")]:
        if os.path.isdir(d):
            shutil.rmtree(d)


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    build_exe()
    zip_path = create_zip()
    cleanup()

    print()
    print(f"Done! Release package: {zip_path}")


if __name__ == "__main__":
    main()
