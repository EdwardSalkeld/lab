"""Regression checks for the generated Chatting deployment's dependency hash."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "update_vendor_hash", Path(__file__).with_name("update-chatting-vendor-hash.py")
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)
OLD_HASH = "sha256-" + "B" * 43 + "="
NEW_HASH = "sha256-" + "C" * 43 + "="
FLAKE = """{
  chattingHandler = pkgs.buildGoModule {
    src = chattingSrc;
    vendorHash = "OLD";
  };
  unrelated = { vendorHash = "do not change"; };
}
""".replace("OLD", OLD_HASH)


def mismatch(value=NEW_HASH):
    return (
        "error: hash mismatch in fixed-output derivation "
        "'/nix/store/example-chatting-handler-2026-07-27-go-modules.drv':\n"
        f"  specified: {updater.FAKE_HASH}\n  got: {value}\n"
    )


class UpdateVendorHashTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.flake = self.repo / "flake.nix"
        self.flake.write_text(FLAKE)

    def test_changed_and_unchanged_dependencies_are_recomputed_and_built(self):
        for value in (NEW_HASH, OLD_HASH):
            with self.subTest(value=value):
                self.flake.write_text(FLAKE)
                calls = []

                def run(command, **kwargs):
                    calls.append(command)
                    self.assertEqual(kwargs["cwd"], self.repo)
                    if len(calls) == 1:
                        self.assertIn(
                            f'vendorHash = "{updater.FAKE_HASH}"',
                            self.flake.read_text(),
                        )
                        return subprocess.CompletedProcess(command, 1, mismatch(value))
                    self.assertIn(f'vendorHash = "{value}"', self.flake.read_text())
                    return subprocess.CompletedProcess(command, 0, "package built\n")

                self.assertEqual(updater.update_vendor_hash(self.repo, run), value)
                self.assertEqual(
                    [c[2] for c in calls],
                    [".#chatting-handler.goModules", ".#chatting-handler"],
                )
                self.assertTrue(all("--no-link" in c for c in calls))
                self.assertEqual(self.flake.read_text(), FLAKE.replace(OLD_HASH, value))

    def test_probe_failure_restores_original_without_building_or_using_stray_hash(self):
        for output in (
            "network failed",
            f"got: {NEW_HASH}",
            mismatch() + mismatch(),
            mismatch().replace("chatting-handler", "unrelated"),
        ):
            with self.subTest(output=output):
                calls = []

                def run(command, **kwargs):
                    calls.append(command)
                    return subprocess.CompletedProcess(command, 1, output)

                with self.assertRaises(RuntimeError):
                    updater.update_vendor_hash(self.repo, run)
                self.assertEqual(len(calls), 1)
                self.assertEqual(self.flake.read_text(), FLAKE)

    def test_failed_verification_restores_original(self):
        results = iter([(1, mismatch()), (1, "build failed")])

        def run(command, **kwargs):
            status, output = next(results)
            return subprocess.CompletedProcess(command, status, output)

        with self.assertRaisesRegex(RuntimeError, "package build failed"):
            updater.update_vendor_hash(self.repo, run)
        self.assertEqual(self.flake.read_text(), FLAKE)

    def test_missing_nix_restores_original(self):
        def run(*args, **kwargs):
            raise FileNotFoundError("nix")

        with self.assertRaises(FileNotFoundError):
            updater.update_vendor_hash(self.repo, run)
        self.assertEqual(self.flake.read_text(), FLAKE)

    def test_unrecognised_flake_does_not_run_nix(self):
        self.flake.write_text("changed structure")

        def run(*args, **kwargs):
            self.fail("must validate the flake before running nix")

        with self.assertRaisesRegex(RuntimeError, "exactly one"):
            updater.update_vendor_hash(self.repo, run)
        self.assertEqual(self.flake.read_text(), "changed structure")


if __name__ == "__main__":
    unittest.main()
