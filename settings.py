"""Persistent app settings — small key/value store (e.g. last selected device)."""

import json
import os

SETTINGS_FILE = os.path.join(os.path.dirname(__file__), "settings.json")


def load_settings() -> dict:
    """Return the settings dict, or {} if no settings file exists."""
    if not os.path.exists(SETTINGS_FILE):
        return {}
    with open(SETTINGS_FILE) as f:
        return json.load(f)


def save_settings(settings: dict) -> None:
    with open(SETTINGS_FILE, "w") as f:
        json.dump(settings, f, indent=2)
