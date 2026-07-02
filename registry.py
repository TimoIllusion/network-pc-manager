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
    The list is sorted: pinned first, then by usage, then alphabetically.
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
            "use_count": existing.get("use_count", 0),
            "pinned": existing.get("pinned", False),
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
                "use_count": info.get("use_count", 0),
                "pinned": info.get("pinned", False),
                "online": mac in online_macs,
            }
        )

    # Sort: pinned devices first, then by usage (descending), then custom-named
    # before generic names, then alphabetically. Online/offline status does not
    # affect ordering.
    result.sort(
        key=lambda d: (
            not d.get("pinned", False),
            -d.get("use_count", 0),
            not bool(d.get("custom_name", "")),
            d["name"].lower(),
        )
    )
    return result


def bump_use_count(mac: str) -> None:
    """Increment the usage counter for a known device (no-op for unknown MACs)."""
    registry = load_registry()
    if mac in registry:
        registry[mac]["use_count"] = registry[mac].get("use_count", 0) + 1
        save_registry(registry)
