"""Sync-profile persistence — stores save-game sync profiles."""

import json
import os
import re

PROFILES_FILE = os.path.join(os.path.dirname(__file__), "sync_profiles.json")


def _slugify(name: str) -> str:
    """Turn a display name into a filesystem-safe slug."""
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "profile"


def load_profiles() -> list[dict]:
    """Return list of sync profiles."""
    if not os.path.exists(PROFILES_FILE):
        return []
    with open(PROFILES_FILE) as f:
        data = json.load(f)
    return data.get("profiles", [])


def save_profiles(profiles: list[dict]) -> None:
    with open(PROFILES_FILE, "w") as f:
        json.dump({"profiles": profiles}, f, indent=2)


def get_profile(profile_id: str) -> dict | None:
    for p in load_profiles():
        if p["id"] == profile_id:
            return p
    return None


def add_profile(name: str, paths: dict[str, str]) -> dict:
    """Create a new profile. Returns the created profile dict."""
    profiles = load_profiles()
    base_id = _slugify(name)
    # Ensure unique ID
    existing_ids = {p["id"] for p in profiles}
    profile_id = base_id
    counter = 2
    while profile_id in existing_ids:
        profile_id = f"{base_id}-{counter}"
        counter += 1
    profile = {"id": profile_id, "name": name, "paths": paths}
    profiles.append(profile)
    save_profiles(profiles)
    return profile


def update_profile(profile_id: str, name: str | None = None, paths: dict[str, str] | None = None) -> dict | None:
    """Update an existing profile. Returns updated profile or None if not found."""
    profiles = load_profiles()
    for p in profiles:
        if p["id"] == profile_id:
            if name is not None:
                p["name"] = name
            if paths is not None:
                p["paths"] = paths
            save_profiles(profiles)
            return p
    return None


def delete_profile(profile_id: str) -> bool:
    """Delete a profile. Returns True if found and deleted."""
    profiles = load_profiles()
    new = [p for p in profiles if p["id"] != profile_id]
    if len(new) == len(profiles):
        return False
    save_profiles(new)
    return True
