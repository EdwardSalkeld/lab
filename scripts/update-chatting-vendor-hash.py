#!/usr/bin/env python3
"""Refresh Chatting's Go dependency hash and verify the updated Nix package."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
VENDOR_HASH = re.compile(
    r'(\bchattingHandler\s*=\s*pkgs\.buildGoModule\s*\{[^}]*?\bvendorHash\s*=\s*")'
    r'([^"\n]+)(")'
)
HASH_MISMATCH = re.compile(
    r"hash mismatch in fixed-output derivation '[^'\n]*chatting-handler[^'\n]*-go-modules\.drv':"
    r"\s+specified:\s+" + re.escape(FAKE_HASH) + r"\s+got:\s+"
    r"(sha256-[A-Za-z0-9+/]{43}=)"
)


def update_vendor_hash(repo: Path, run=subprocess.run) -> str:
    flake = repo / "flake.nix"
    original = flake.read_text()
    matches = list(VENDOR_HASH.finditer(original))
    if len(matches) != 1:
        raise RuntimeError(
            "expected exactly one chattingHandler vendorHash in flake.nix"
        )
    match = matches[0]

    def write_hash(value: str) -> None:
        flake.write_text(original[: match.start(2)] + value + original[match.end(2) :])

    def build(target: str) -> subprocess.CompletedProcess:
        result = run(
            ["nix", "build", target, "--no-link", "--print-build-logs"],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print(result.stdout, end="", flush=True)
        return result

    try:
        # Always force a fresh dependency calculation. Keeping the previous hash
        # can reuse a cached fixed-output path even when go.mod/go.sum changed.
        write_hash(FAKE_HASH)
        probe = build(".#chatting-handler.goModules")
        hashes = HASH_MISMATCH.findall(probe.stdout)
        if probe.returncode == 0 or len(hashes) != 1 or hashes[0] == FAKE_HASH:
            raise RuntimeError(
                "Nix did not report the expected Chatting Go dependency hash"
            )
        write_hash(hashes[0])
        verified = build(".#chatting-handler")
        if verified.returncode != 0:
            raise RuntimeError(
                "Chatting package build failed with the refreshed dependency hash"
            )
        return hashes[0]
    except BaseException:
        # Never leave a placeholder or unverified hash for the PR action to pick up.
        flake.write_text(original)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        value = update_vendor_hash(args.repo.resolve())
    except (OSError, RuntimeError) as error:
        print(f"Cannot update Chatting vendorHash: {error}", file=sys.stderr)
        return 1
    print(f"Verified Chatting vendorHash: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
