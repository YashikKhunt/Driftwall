#!/usr/bin/env python3
"""Validate untrusted Community catalog metadata and files; no media decode."""
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import urlsplit

MAX_CATALOG = 1024 * 1024
MAX_ITEMS = 100
MAX_FILE = 200 * 1024 * 1024
MAX_TOTAL = 500 * 1024 * 1024
REQUIRED = {"id", "title", "description", "artist", "license", "category", "filename", "sha256"}
ALLOWED = REQUIRED | {"profileURL"}
CATEGORIES = {"Nature", "Ocean", "Space", "Abstract", "Minimal"}
LICENSES = {"CC0-1.0", "CC-BY-4.0"}
ID = re.compile(r"^community-[a-z0-9]+(?:-[a-z0-9]+)*$")
FILENAME = re.compile(r"^[a-z0-9][a-z0-9._-]*\.(?:mp4|mov)$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message):
    raise ValueError(message)


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("duplicate JSON key")
        result[key] = value
    return result


def plain_text(value, maximum, field):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        fail(f"invalid {field}")
    if any(unicodedata.category(char) in {"Cc", "Cf"} for char in value):
        fail(f"invalid {field}")


def profile_url(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 300:
        fail("invalid profileURL")
    if any(char.isspace() or unicodedata.category(char) in {"Cc", "Cf"} for char in value):
        fail("invalid profileURL")
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.port is not None
            or parsed.query or parsed.fragment):
        fail("invalid profileURL")


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def validate(community_directory):
    community = Path(community_directory)
    if community.is_symlink() or not community.is_dir():
        fail("missing or unsafe Community directory")
    community = community.resolve()
    catalog = community / "catalog.json"
    assets = community / "Assets"
    if catalog.is_symlink() or not catalog.is_file():
        fail("missing or unsafe catalog.json")
    if catalog.stat().st_size > MAX_CATALOG:
        fail("catalog exceeds 1 MiB")
    try:
        data = json.loads(catalog.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        fail(f"invalid JSON: {error}")
    if (not isinstance(data, dict) or set(data) != {"schemaVersion", "wallpapers"}
            or type(data["schemaVersion"]) is not int or data["schemaVersion"] != 1
            or not isinstance(data["wallpapers"], list)):
        fail("invalid catalog schema")
    items = data["wallpapers"]
    if len(items) > MAX_ITEMS:
        fail("too many wallpapers")
    if assets.is_symlink() or not assets.is_dir():
        fail("missing or unsafe Assets directory")
    assets = assets.resolve()
    ids, filenames, total = set(), set(), 0
    for item in items:
        if not isinstance(item, dict) or set(item) - ALLOWED or REQUIRED - set(item):
            fail("invalid wallpaper keys")
        plain_text(item["title"], 80, "title")
        plain_text(item["description"], 280, "description")
        plain_text(item["artist"], 80, "artist")
        identifier = item["id"]
        if not isinstance(identifier, str) or len(identifier) > 80 or not ID.fullmatch(identifier) or identifier in ids:
            fail("invalid or duplicate id")
        if not isinstance(item["license"], str) or item["license"] not in LICENSES:
            fail("invalid license")
        if not isinstance(item["category"], str) or item["category"] not in CATEGORIES:
            fail("invalid category")
        filename = item["filename"]
        if not isinstance(filename, str) or len(filename) > 160 or not FILENAME.fullmatch(filename) or filename in filenames:
            fail("invalid or duplicate filename")
        if not isinstance(item["sha256"], str) or not SHA256.fullmatch(item["sha256"]):
            fail("invalid sha256")
        if "profileURL" in item:
            profile_url(item["profileURL"])
        asset = assets / filename
        if asset.is_symlink() or not asset.is_file() or asset.resolve().parent != assets:
            fail(f"missing or unsafe asset: {filename}")
        size = asset.stat().st_size
        if size == 0 or size > MAX_FILE:
            fail(f"invalid asset size: {filename}")
        total += size
        if total > MAX_TOTAL:
            fail("assets exceed 500 MiB")
        if file_hash(asset) != item["sha256"]:
            fail(f"hash mismatch: {filename}")
        ids.add(identifier)
        filenames.add(filename)
    for entry in assets.iterdir():
        if entry.name == ".gitkeep":
            if entry.is_symlink() or not entry.is_file():
                fail("unsafe .gitkeep")
        elif entry.name not in filenames:
            fail("unexpected file in Assets")
    return len(items)


if __name__ == "__main__":
    try:
        location = sys.argv[1] if len(sys.argv) == 2 else "Community"
        print(f"PASS: validated {validate(location)} community wallpapers")
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
