"""Exercise actual macOS QA process guards without opening a network endpoint."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "packages/together-p2p-swift/.build/debug/TogetherP2PPublicQA"


@unittest.skipUnless(sys.platform == "darwin" and CLI.is_file(),
                     "Requires the built isolated macOS QA executable")
class NativeRootGuardTests(unittest.TestCase):
    def test_missing_and_production_root_are_refused(self):
        production = str(Path.home() / "Library/Application Support/Together")
        for arguments in ([], ["--root", production], ["--reopen-root", production]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(CLI), *arguments], capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 1)

    def test_system_temporary_alias_accepts_only_new_isolated_identity(self):
        # Python realpath and Foundation differ for /private/tmp vs /tmp. This
        # reproduces the actual first physical-run initialization failure.
        with tempfile.TemporaryDirectory(prefix="together-p2p-public-", dir="/tmp") as name:
            directory = Path(name).resolve()
            directory.chmod(0o700)
            (directory / "launch.json").write_text(json.dumps({
                "role": "initiator", "mode": "directOnly", "deadlineSeconds": 30,
            }))
            child = subprocess.Popen([str(CLI), "--root", str(directory)],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 5
                descriptor = directory / "descriptor.json"
                while not descriptor.is_file() and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertTrue(descriptor.is_file(), "A permitted system-temp alias was rejected")
                self.assertIsNone(child.poll())
                self.assertEqual(json.loads(descriptor.read_text())["protocolVersion"], 4)
                keys = list((directory / "identity").glob("*.key"))
                self.assertEqual(len(keys), 1)
                self.assertEqual(keys[0].stat().st_size, 32)
                self.assertEqual(keys[0].stat().st_mode & 0o777, 0o600)
                self.assertFalse((directory / "qa.store").exists())
                self.assertFalse((directory / "contact.json").exists())
            finally:
                if child.poll() is None:
                    child.terminate()
                child.communicate(timeout=5)

    def test_reopen_missing_state_never_creates_replacement_identity_or_store(self):
        with tempfile.TemporaryDirectory(prefix="together-p2p-public-", dir="/tmp") as name:
            directory = Path(name).resolve()
            result = subprocess.run([str(CLI), "--reopen-root", str(directory)],
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertFalse((directory / "identity").exists())
            self.assertFalse((directory / "metadata.json").exists())
            self.assertFalse((directory / "qa.store").exists())


if __name__ == "__main__":
    unittest.main()
