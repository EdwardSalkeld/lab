#!/usr/bin/env bash
set -euo pipefail

DEST_ROOT="${1:-/mnt/ssd4tb/docker-volumes}"

volumes=(
  docker_pigallery2-storage
  docker_jfconfig
  docker_jfcache
  chatting_handler-data
  chatting_worker-data
  chatting_html-output
  chatting_shared-temp
  chatting_codex-auth
  chatting_claude-auth
  chatting_gh-auth
)

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root so Docker volume ownership and metadata are preserved" >&2
  exit 1
fi

mkdir -p "${DEST_ROOT}"

for volume in "${volumes[@]}"; do
  source_dir="$(docker volume inspect --format '{{ .Mountpoint }}' "${volume}")"
  dest_dir="${DEST_ROOT}/${volume}"

  if [[ ! -d "${source_dir}" ]]; then
    echo "missing source for ${volume}: ${source_dir}" >&2
    exit 1
  fi

  mkdir -p "${dest_dir}"
  rsync -aHAX --numeric-ids "${source_dir}/" "${dest_dir}/"
  echo "${volume} -> ${dest_dir}"
done
