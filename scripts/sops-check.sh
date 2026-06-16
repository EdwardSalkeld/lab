#!/usr/bin/env bash
set -euo pipefail

if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$repo_root"

mapfile -t expected_recipients < <(
  awk '
    /^[[:space:]]*- &/ {
      sub(/^[^"]*"/, "")
      sub(/".*/, "")
      print
    }
  ' .sops.yaml
)

if [[ "${#expected_recipients[@]}" -eq 0 ]]; then
  echo "no expected sops recipients found in .sops.yaml" >&2
  exit 1
fi

mapfile -t secret_files < <(
  find nixos/hosts -path '*/secrets/*.yaml' ! -name '*.example' -type f | sort
)

if [[ "${#secret_files[@]}" -eq 0 ]]; then
  echo "no sops secret files found" >&2
  exit 1
fi

failed=0

for secret_file in "${secret_files[@]}"; do
  if ! grep -q '^sops:' "$secret_file"; then
    echo "missing sops metadata: $secret_file" >&2
    failed=1
    continue
  fi

  for recipient in "${expected_recipients[@]}"; do
    if ! grep -Fq "recipient: $recipient" "$secret_file"; then
      echo "missing recipient in $secret_file: $recipient" >&2
      failed=1
    fi
  done
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf 'checked %d sops file(s) against %d recipient(s)\n' \
  "${#secret_files[@]}" \
  "${#expected_recipients[@]}"
