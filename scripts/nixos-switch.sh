#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTNAME_SHORT="$(hostname -s)"
ACTION="${1:-switch}"
ROLLBACK_FLAG=()

case "${ACTION}" in
  switch | boot | test | build | dry-build) ;;
  rollback)
    ACTION="switch"
    ROLLBACK_FLAG=(--rollback)
    ;;
  *)
    echo "usage: $0 [switch|boot|test|build|dry-build|rollback]" >&2
    exit 2
    ;;
esac

cd "${ROOT_DIR}"
exec sudo nixos-rebuild "${ACTION}" "${ROLLBACK_FLAG[@]}" --flake ".#${HOSTNAME_SHORT}"
