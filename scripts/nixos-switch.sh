#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTNAME_SHORT="$(hostname -s)"
ACTION="${1:-switch}"

case "${ACTION}" in
  switch | boot | test | build | dry-build | rollback) ;;
  *)
    echo "usage: $0 [switch|boot|test|build|dry-build|rollback]" >&2
    exit 2
    ;;
esac

cd "${ROOT_DIR}"
exec sudo nixos-rebuild "${ACTION}" --flake ".#${HOSTNAME_SHORT}"
