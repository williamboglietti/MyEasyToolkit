#!/usr/bin/env python3
"""Tests using disposable authority and project OpenPGP keys only."""

import datetime
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "packaging"))
import apt_trust_refresh as trust  # noqa: E402
import apt_trust_guard as guard  # noqa: E402


class TrustTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="met-apt-authority-")
        cls.home = Path(cls.tmp.name)
        os.chmod(str(cls.home), 0o700)
        (cls.home / "gpg-agent.conf").write_text("disable-scdaemon\n")
        cls.project_uid = "TEST MyEasyToolkit <met@example.invalid>"
        cls.root = cls.generate("TEST authority <root@example.invalid>", "cert")
        cls.a = cls.generate(cls.project_uid, "sign")
        cls.b = cls.generate(cls.project_uid, "sign")
        cls.other = cls.generate("TEST other project <other@example.invalid>", "sign")
        for key in (cls.a, cls.other):
            cls.gpg("--default-cert-expire", "1d", "--local-user", cls.root + "!", "--quick-sign-key", key)
        cls.authority = cls.gpg("--export", cls.root + "!")
        cls.before = cls.gpg("--export", cls.a, cls.b, cls.other)
        cls.signatures = {key: cls.gpg("--local-user", key + "!", "--detach-sign", data=b"test")
                          for key in (cls.a, cls.b, cls.other)}
        # The interactive command also works with GnuPG 2.2 on Debian 10.
        cls.gpg("--local-user", cls.root + "!", "--command-fd", "0", "--status-fd", "1",
                "--edit-key", cls.a, data=b"revsig\nn\ny\ny\n0\n\ny\nsave\n")
        cls.gpg("--default-cert-expire", "1d", "--local-user", cls.root + "!", "--quick-sign-key", cls.b)
        cls.after = cls.gpg("--export", cls.a, cls.b, cls.other)
        cls.private = cls.gpg("--export-secret-keys", cls.a)
        no_expiry = cls.generate(cls.project_uid, "sign")
        cls.gpg("--local-user", cls.root + "!", "--quick-sign-key", no_expiry)
        cls.no_expiry = cls.gpg("--export", no_expiry)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", str(cls.home), "--kill", "gpg-agent"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        cls.tmp.cleanup()

    @classmethod
    def gpg(cls, *args, data=None):
        result = subprocess.run(
            ["gpg", "--homedir", str(cls.home), "--batch", "--yes", "--no-tty",
             "--pinentry-mode", "loopback", "--passphrase", "", *args],
            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.decode("utf-8", "replace"))
        return result.stdout

    @classmethod
    def generate(cls, uid, usage):
        def fingerprints():
            rows = cls.gpg("--with-colons", "--list-keys").decode().splitlines()
            return {row.split(":")[9] for row in rows if row.startswith("fpr:")}
        old = fingerprints()
        cls.gpg("--quick-generate-key", uid, "ed25519", usage, "5d")
        return (fingerprints() - old).pop()

    def verify(self, cached, received, now=None):
        return trust.verify_certificates(self.authority, cached, received, self.root, self.project_uid, now=now)

    def test_project_scope_and_replacement(self):
        first, cached, ids, _ = self.verify(b"", self.before)
        self.assertEqual(ids, [self.a])
        second, cached, ids, _ = self.verify(cached, self.after)
        self.assertEqual(ids, [self.b])
        _, _, ids, _ = self.verify(cached, self.before)
        self.assertEqual(ids, [self.b])
        path = self.home / "filtered.gpg"
        message = self.home / "message"
        path.write_bytes(second)
        message.write_bytes(b"test")
        for key in (self.a, self.b, self.other):
            signature = self.home / (key + ".sig")
            signature.write_bytes(self.signatures[key])
            result = subprocess.run(["gpgv", "--homedir", str(self.home), "--keyring", str(path),
                                     str(signature), str(message)], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
            self.assertEqual(result.returncode == 0, key == self.b)
        self.assertTrue(first)

    def test_expired_or_forged_certification_is_rejected(self):
        with self.assertRaises(trust.TrustError):
            self.verify(b"", self.before, now=int(time.time()) + 2 * 86400)
        with self.assertRaises(trust.TrustError):
            self.verify(b"", self.before.replace(b"MyEasyToolkit", b"MyEasyToolkiX"))
        with self.assertRaises(trust.TrustError):
            trust.verify_certificates(self.authority, b"", self.before, "0" * 40, self.project_uid)
        with self.assertRaises(trust.TrustError):
            self.verify(b"", self.private)
        with self.assertRaises(trust.TrustError):
            self.verify(b"", self.no_expiry)

    def test_outage_blocks_and_recovery_unblocks(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-refresh-") as directory:
            p = Path(directory)
            authority, state, active, block = p / "root.gpg", p / "state", p / "active.gpg", p / "block"
            authority.write_bytes(self.authority)
            result = trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.before)
            self.assertEqual(result, [self.a])
            self.assertTrue(active.exists())
            self.assertFalse(block.exists())

            def offline():
                raise OSError("offline")

            with self.assertRaises(trust.TrustError):
                trust.refresh(authority, state, active, block, self.root, self.project_uid, offline)
            self.assertFalse(active.exists())
            self.assertEqual(block.read_bytes(), trust.block_file(trust.REPO_HOST))
            result = trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.after)
            self.assertEqual(result, [self.b])
            self.assertFalse(block.exists())

    def test_damaged_persistent_state_stays_blocked(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-refresh-") as directory:
            p = Path(directory)
            authority, state, active, block = p / "root.gpg", p / "state", p / "active.gpg", p / "block"
            authority.write_bytes(self.authority)
            trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.before)
            (state / "certificates.gpg").write_bytes(b"corrupted")
            with self.assertRaises(trust.TrustError):
                trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.after)
            self.assertFalse(active.exists())
            self.assertEqual(block.read_bytes(), trust.block_file(trust.REPO_HOST))

    def test_failed_keyring_write_keeps_origin_blocked(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-refresh-") as directory:
            p = Path(directory)
            authority, state, active, block = p / "root.gpg", p / "state", p / "active.gpg", p / "block"
            authority.write_bytes(self.authority)
            original = trust._atomic_write

            def interrupted(path, data, mode):
                if path == active:
                    path.write_bytes(data)
                    raise OSError("simulated failure after replacement")
                return original(path, data, mode)

            with mock.patch.object(trust, "_atomic_write", side_effect=interrupted):
                with self.assertRaises(trust.TrustError):
                    trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.before)
            self.assertFalse(active.exists())
            self.assertEqual(block.read_bytes(), trust.block_file(trust.REPO_HOST))

    def test_failed_pin_write_invalidates_the_active_keyring(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-pin-") as directory:
            p = Path(directory)
            active, block = p / "active.gpg", p / "block"
            active.write_bytes(b"old keyring")
            with mock.patch.object(trust, "_atomic_write", side_effect=OSError("read-only")):
                with self.assertRaises(OSError):
                    trust._block_origin(active, block, trust.REPO_HOST)
            self.assertFalse(active.exists())

    def test_download_limits_and_failure(self):
        opener = mock.Mock()
        with mock.patch.object(trust.urllib.request, "build_opener", return_value=opener):
            for contents in (b"", b"x" * (trust.MAX_CERT_SIZE + 1)):
                opener.open.return_value = io.BytesIO(contents)
                with self.assertRaises(trust.TrustError):
                    trust.download_catalog()
            opener.open.side_effect = OSError("offline")
            with self.assertRaises(trust.TrustError):
                trust.download_catalog()

    def test_install_guard_checks_only_project_packages(self):
        prefix = b"VERSION 2\nDir::State::lists=/tmp/lists\n\n"
        project = prefix + b"myeasytoolkit - < 1.0 /tmp/file.deb\n"
        other = prefix + b"openssl - < 1.0 /tmp/file.deb\n"
        remove = prefix + b"myeasytoolkit 1.0 > - **REMOVE**\n"
        requested, config = guard.apt_request(io.BytesIO(project))
        self.assertTrue(requested)
        self.assertEqual(config["Dir::State::lists"], "/tmp/lists")
        self.assertFalse(guard.apt_request(io.BytesIO(other))[0])
        self.assertFalse(guard.apt_request(io.BytesIO(remove))[0])

    def test_cached_release_must_use_current_project_key(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-lists-") as directory:
            p = Path(directory)
            config, active = p / "config.json", p / "active.gpg"
            config.write_text('{"catalog_url":"https://packages.example/apt/certificates.gpg",'
                              '"repo_host":"packages.example"}')
            active.write_bytes(self.verify(b"", self.after)[0])
            release = p / "packages.example_apt_dists_stable_InRelease"
            apt_config = {"Dir::State::lists": str(p)}
            release.write_bytes(self.gpg("--local-user", self.a + "!", "--clearsign", data=b"test\n"))
            self.assertFalse(guard.cached_release_is_trusted(config, active, apt_config))
            release.write_bytes(self.gpg("--local-user", self.b + "!", "--clearsign", data=b"test\n"))
            self.assertTrue(guard.cached_release_is_trusted(config, active, apt_config))
            release.unlink()
            self.assertFalse(guard.cached_release_is_trusted(config, active, apt_config))

    def test_install_guard_expires_and_detects_tampering(self):
        with tempfile.TemporaryDirectory(prefix="met-apt-guard-") as directory:
            p = Path(directory)
            authority, state, active, block, config = p / "root.gpg", p / "state", p / "active.gpg", p / "block", p / "config.json"
            authority.write_bytes(self.authority)
            config.write_text('{{"authority_fingerprint":"{}","project_uid":"{}"}}'.format(
                self.root, self.project_uid))
            trust.refresh(authority, state, active, block, self.root, self.project_uid, lambda: self.before)
            self.assertTrue(guard.trust_is_current(config, state, active, block))
            self.assertFalse(guard.trust_is_current(config, state, active, block, now=int(time.time()) + 2 * 86400))
            active.write_bytes(b"tampered")
            self.assertFalse(guard.trust_is_current(config, state, active, block))


if __name__ == "__main__":
    unittest.main()
