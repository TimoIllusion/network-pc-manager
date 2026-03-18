"""Persistent device registry — stores known devices keyed by MAC address."""

import json
import os

REGISTRY_FILE = os.path.join(os.path.dirname(__file__), "devices.json")


def load_registry() -> dict:
    """Return dict of known devices keyed by MAC (uppercase)."""
    if not os.path.exists(REGISTRY_FILE):
        return {}
    with open(REGISTRY_FILE) as f:
        return json.load(f)


def save_registry(registry: dict) -> None:
    with open(REGISTRY_FILE, "w") as f:
        json.dump(registry, f, indent=2)


def merge_scan(scan_results: list[dict]) -> list[dict]:
    """Merge a live scan with the persisted registry.

    Online devices update the registry (refreshing their IP / name).
    Offline devices are returned from the registry with online=False and ip="".
    The list is sorted: online devices first, then alphabetically by name.
    """
    registry = load_registry()

    online_macs: set[str] = set()
    for device in scan_results:
        mac = device["mac"]
        online_macs.add(mac)
        existing = registry.get(mac, {})
        registry[mac] = {
            "ip": device["ip"],
            "mac": mac,
            "name": device["name"],
            "custom_name": existing.get("custom_name", ""),
        }

    save_registry(registry)

    result = []
    for mac, info in registry.items():
        result.append(
            {
                "ip": info["ip"] if mac in online_macs else "",
                "mac": mac,
                "name": info["name"],
                "custom_name": info.get("custom_name", ""),
                "online": mac in online_macs,
            }
        )

    # Sort: online first, then offline; within each group custom-named entries first,
    # then alphabetically by name (case-insensitive).
    result.sort(key=lambda d: (not d["online"], not bool(d.get("custom_name", "")), d["name"].lower()))
    return result
