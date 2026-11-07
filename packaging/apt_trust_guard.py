#!/usr/bin/python3
"""Protect MyEasyToolkit package installs when its trust is unavailable."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import unquote, urlsplit


PACKAGES = frozenset(("myeasytoolkit", "myeasytoolkit-archive-keyring"))
MAX_FILE = 1024 * 1024


def trust_is_current(config_path, state_dir, active_keyring, block_path, now=None):
    if now is None:
        now = int(time.time())
    config_path, state_dir = Path(config_path), Path(state_dir)
    active_keyring, block_path = Path(active_keyring), Path(block_path)
    if block_path.exists():
        return False
    try:
        if any(path.stat().st_size > MAX_FILE for path in
               (config_path, state_dir / "trust.json", state_dir / "certificates.gpg", active_keyring)):
            return False
        config = json.loads(config_path.read_text(encoding="utf-8"))
        metadata = json.loads((state_dir / "trust.json").read_text(encoding="utf-8"))
        expiry = metadata["valid_until"]
        return (isinstance(expiry, int) and not isinstance(expiry, bool) and expiry > now
                and metadata["authority"] == config["authority_fingerprint"]
                and metadata["project_uid"] == config["project_uid"]
                and metadata["keyring_sha256"] == hashlib.sha256(active_keyring.read_bytes()).hexdigest()
                and metadata["catalog_sha256"] == hashlib.sha256(
                    (state_dir / "certificates.gpg").read_bytes()).hexdigest())
    except (OSError, ValueError, KeyError, TypeError):
        return False


def apt_request(stream):
    """Read the APT Pre-Install-Pkgs v2 protocol, ignoring removals."""
    version = None
    in_actions = False
    found = False
    config = {}
    for raw in stream:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if version is None:
            version = line
        elif not in_actions and not line:
            in_actions = True
        elif not in_actions and "=" in line:
            key, value = line.split("=", 1)
            config[key] = unquote(value)
        elif in_actions:
            fields = line.split(None, 4)
            if (len(fields) == 5 and fields[0].split(":", 1)[0] in PACKAGES
                    and fields[4] != "**REMOVE**"):
                found = True
    return version == "VERSION 2" and in_actions and found, config


def cached_release_is_trusted(config_path, active_keyring, apt_config):
    """Refuse stale APT lists signed by a project key that was withdrawn."""
    try:
        config = json.loads(Path(config_path).read_text(encoding="utf-8"))
        url = urlsplit(config["catalog_url"])
        host = config["repo_host"]
        if url.hostname != host or url.scheme != "https":
            return False
        authority = host + (":" + str(url.port) if url.port else "")
        root = Path(apt_config.get("Dir", "/"))
        state = root / apt_config.get("Dir::State", "var/lib/apt")
        lists = state / apt_config.get("Dir::State::lists", "lists")
        release = lists / (authority + "_apt_dists_stable_InRelease")
        if release.stat().st_size > 4 * MAX_FILE:
            return False
        result = subprocess.run(["gpgv", "--keyring", str(active_keyring), str(release)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=15, check=False)
        return result.returncode == 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        return False


def main():
    requested, apt_config = apt_request(sys.stdin.buffer)
    base = Path("/usr/share/myeasytoolkit-archive-keyring")
    active = "/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg"
    if (requested and (not trust_is_current(base / "config.json", "/var/lib/myeasytoolkit-archive-keyring",
                                            active, "/etc/apt/preferences.d/99myeasytoolkit-block")
                       or not cached_release_is_trusted(base / "config.json", active, apt_config))):
        print("MyEasyToolkit : installation suspendue ; exécutez apt update après rétablissement de la confiance.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
