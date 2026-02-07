#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${ROOT_DIR}/.kubeconfig"

terraform -chdir="${ROOT_DIR}/terraform/lab" output -raw kubeconfig > "${OUTPUT}"
echo "Wrote kubeconfig to ${OUTPUT}"
