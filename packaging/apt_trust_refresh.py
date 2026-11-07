#!/usr/bin/python3
"""Verify project-key certifications and refresh scoped APT trust.

Only public OpenPGP certificates are processed.  The certification authority
is pinned independently of the project key used by the release CI.
"""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


MAX_CERT_SIZE = 1024 * 1024
MAX_STATE_SIZE = 2 * MAX_CERT_SIZE
FINGERPRINT = re.compile(r"[A-F0-9]{40}")
SAFE_UID = re.compile(r"[A-Za-z0-9 ._+@<>(),=-]{5,200}")
REPO_HOST = "packages.myeasytoolkit.com"
CATALOG_URL = "https://packages.myeasytoolkit.com/apt/certificates.gpg"
HOST = re.compile(r"[A-Za-z0-9.-]{1,253}")


class TrustError(Exception):
    """A trust update could not be authenticated."""


def block_file(repo_host):
    if not isinstance(repo_host, str) or not HOST.fullmatch(repo_host):
        raise TrustError("nom de dépôt invalide")
    return ("Package: myeasytoolkit myeasytoolkit-archive-keyring\n"
            "Pin: origin \"{}\"\nPin-Priority: -1\n").format(repo_host).encode("ascii")


def _gpg(home, *args, data=None):
    env = os.environ.copy()
    env["GNUPGHOME"] = str(home)
    env["LC_ALL"] = "C"
    try:
        result = subprocess.run(
            ["gpg", "--no-options", "--batch", "--no-tty", *args], input=data,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=30, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TrustError("GnuPG indisponible ou délai dépassé") from exc
    if result.returncode:
        raise TrustError("certificat OpenPGP invalide")
    return result.stdout


def _import_public(home, certificate):
    if not isinstance(certificate, bytes) or not certificate or len(certificate) > MAX_CERT_SIZE:
        raise TrustError("certificat vide ou trop volumineux")
    packets = _gpg(home, "--list-packets", data=certificate)
    if re.search(rb"^:secret (?:sub )?key packet:", packets, re.M):
        raise TrustError("une clé privée ne doit pas être importée")
    _gpg(home, "--import", data=certificate)


def verify_certificates(authority, cached, received, authority_fpr, project_uid, now=None):
    """Return (scoped keyring, merged public certificates, approved key IDs).

    The project identity must be self-certified and have a current, non-revoked,
    time-limited certification directly from the pinned authority.  A revoked
    authority certification is treated as permanent for that project key.
    """
    if not FINGERPRINT.fullmatch(authority_fpr) or not SAFE_UID.fullmatch(project_uid):
        raise TrustError("configuration de confiance invalide")
    if now is None:
        now = int(time.time())
    with tempfile.TemporaryDirectory(prefix="met-apt-trust-") as temporary:
        home = Path(temporary)
        os.chmod(str(home), 0o700)
        try:
            _import_public(home, authority)
            root_listing = _gpg(home, "--with-colons", "--with-fingerprint", "--list-keys").decode().splitlines()
            root_keys = []
            pending = False
            for line in root_listing:
                fields = line.split(":")
                if fields[0] == "pub":
                    pending = True
                elif fields[0] == "fpr" and pending:
                    root_keys.append(fields[9])
                    pending = False
            if root_keys != [authority_fpr]:
                raise TrustError("clé principale inattendue")
            if cached:
                _import_public(home, cached)
            _import_public(home, received)

            rows = _gpg(home, "--with-colons", "--with-fingerprint", "--check-sigs").decode("utf-8", "strict").splitlines()
            candidates = {}
            root_ok = False
            key = None
            key_status = None
            key_caps = ""
            waiting_fpr = False
            uid = None

            def finish_uid():
                if (uid is not None and uid["self_signed"] and uid["certified"]
                        and not uid["revoked"]):
                    candidates[uid["key"]] = max(candidates.get(uid["key"], 0), uid["cert_until"])

            for line in rows:
                fields = line.split(":")
                if fields[0] == "pub":
                    finish_uid()
                    uid = None
                    key = None
                    key_status, key_caps = fields[1], fields[11]
                    waiting_fpr = True
                elif fields[0] == "fpr" and waiting_fpr:
                    key = fields[9]
                    waiting_fpr = False
                    if key == authority_fpr and key_status not in ("r", "e", "d", "i"):
                        root_ok = True
                elif fields[0] == "uid":
                    finish_uid()
                    uid = None
                    if (key and key != authority_fpr and key_status not in ("r", "e", "d", "i")
                            and "s" in key_caps and fields[1] not in ("r", "e", "d", "i")
                            and fields[9] == project_uid):
                        uid = {"key": key, "self_signed": False, "certified": False,
                               "cert_until": 0, "revoked": False}
                elif fields[0] in ("sub", "uat"):
                    finish_uid()
                    uid = None
                elif uid is not None and len(fields) > 12 and fields[1] == "!":
                    kind = fields[0]
                    signer = fields[12]
                    sig_type = fields[10][:2]
                    created, expires = fields[5], fields[6]
                    if kind == "rev" and signer == authority_fpr and sig_type == "30":
                        uid["revoked"] = True
                    if kind == "sig" and sig_type in ("10", "11", "12", "13"):
                        if signer == uid["key"]:
                            uid["self_signed"] = True
                        if (signer == authority_fpr and created.isdigit() and expires.isdigit()
                                and int(created) <= now + 300 and int(expires) > now):
                            uid["certified"] = True
                            uid["cert_until"] = max(uid["cert_until"], int(expires))
            finish_uid()
            keys = sorted(candidates)
            if not root_ok or not keys:
                raise TrustError("aucune clé de projet certifiée et valide")
            filtered = _gpg(home, "--export", *(key + "!" for key in keys))
            merged = _gpg(home, "--export")
            if not filtered or not merged or len(merged) > MAX_CERT_SIZE:
                raise TrustError("trousseau public vide ou trop volumineux")
            return filtered, merged, keys, min(candidates.values())
        finally:
            subprocess.run(["gpgconf", "--homedir", str(home), "--kill", "gpg-agent"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


def download_catalog(url=CATALOG_URL):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.fragment or not HOST.fullmatch(parsed.hostname)):
        raise TrustError("adresse HTTPS du catalogue invalide")
    request = urllib.request.Request(url, headers={"User-Agent": "MyEasyToolkit-Archive-Keyring/1"})
    opener = urllib.request.build_opener(_NoRedirect())
    deadline = time.monotonic() + 15
    parts = []
    size = 0
    try:
        with opener.open(request, timeout=10) as response:
            while True:
                if time.monotonic() > deadline:
                    raise TrustError("délai de téléchargement dépassé")
                part = response.read(min(65536, MAX_CERT_SIZE + 1 - size))
                if not part:
                    break
                size += len(part)
                if size > MAX_CERT_SIZE:
                    raise TrustError("catalogue trop volumineux")
                parts.append(part)
    except (OSError, urllib.error.URLError) as exc:
        raise TrustError("catalogue de confiance inaccessible") from exc
    if not size:
        raise TrustError("catalogue de confiance vide")
    return b"".join(parts)


def _atomic_write(path, data, mode):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=".met-", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, str(path))
        directory = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _block_origin(active_keyring, block_path, repo_host):
    try:
        _atomic_write(block_path, block_file(repo_host), 0o644)
    finally:
        # Invalidate the keyring even if creating the preferences file fails.
        try:
            Path(active_keyring).unlink()
        except FileNotFoundError:
            pass


def refresh(authority_path, state_dir, active_keyring, block_path, authority_fpr, project_uid, fetch,
            now=None, repo_host=REPO_HOST):
    """Refresh a single origin, blocking it until verification succeeds."""
    authority_path, state_dir = Path(authority_path), Path(state_dir)
    active_keyring, block_path = Path(active_keyring), Path(block_path)
    # Block before contacting the network, including when stale APT lists exist.
    _block_origin(active_keyring, block_path, repo_host)
    state_dir.mkdir(mode=0o755, parents=True, exist_ok=True)
    active_keyring.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    with (state_dir / "refresh.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Another invocation could have re-enabled the origin while we waited.
        _block_origin(active_keyring, block_path, repo_host)
        try:
            cached_path = state_dir / "certificates.gpg"
            metadata_path = state_dir / "trust.json"
            if metadata_path.exists():
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                cached = cached_path.read_bytes()
                if (metadata.get("authority") != authority_fpr
                        or metadata.get("catalog_sha256") != hashlib.sha256(cached).hexdigest()):
                    raise TrustError("état de confiance incohérent")
            else:
                if cached_path.exists():
                    raise TrustError("état de confiance incomplet")
                cached = b""
            filtered, merged, keys, valid_until = verify_certificates(
                authority_path.read_bytes(), cached, fetch(), authority_fpr, project_uid, now=now
            )
            _atomic_write(cached_path, merged, 0o600)
            _atomic_write(active_keyring, filtered, 0o644)
            metadata = json.dumps({"authority": authority_fpr, "project_uid": project_uid,
                                   "valid_until": valid_until,
                                   "catalog_sha256": hashlib.sha256(merged).hexdigest(),
                                   "keyring_sha256": hashlib.sha256(filtered).hexdigest()},
                                  sort_keys=True).encode("utf-8")
            _atomic_write(metadata_path, metadata, 0o600)
            block_path.unlink()
            return keys
        except (OSError, ValueError, TrustError) as exc:
            # If a write failed after replacement, keep the origin blocked.
            try:
                active_keyring.unlink()
            except FileNotFoundError:
                pass
            raise TrustError("actualisation de confiance impossible") from exc


def main():
    base = Path("/usr/share/myeasytoolkit-archive-keyring")
    active = Path("/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg")
    block = Path("/etc/apt/preferences.d/99myeasytoolkit-block")
    try:
        # Even a damaged configuration must not leave the previous key active.
        _block_origin(active, block, REPO_HOST)
        config = json.loads((base / "config.json").read_text(encoding="utf-8"))
        refresh(base / "authority.gpg", "/var/lib/myeasytoolkit-archive-keyring",
                active, block,
                config["authority_fingerprint"], config["project_uid"],
                lambda: download_catalog(config["catalog_url"]), repo_host=config["repo_host"])
        print("MyEasyToolkit : clés de confiance actualisées.")
    except (OSError, ValueError, KeyError, TrustError) as exc:
        print("MyEasyToolkit : vérification de confiance impossible ({})".format(exc),
              file=sys.stderr)
        # Do not fail the whole APT update solely because this origin is down.
        # The scoped pin and install guard keep the project unavailable.
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
