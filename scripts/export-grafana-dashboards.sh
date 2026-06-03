#!/usr/bin/env bash
set -euo pipefail

grafana_url="${OLD_GRAFANA_URL:-https://grafana.b.alcachofa.faith}"
output_dir="${1:-grafana-dashboard-exports/$(date -u +%Y%m%dT%H%M%SZ)}"

if [ -z "${OLD_GRAFANA_TOKEN:-}" ]; then
  echo "OLD_GRAFANA_TOKEN is required" >&2
  exit 1
fi

mkdir -p "$output_dir"

api() {
  local path="$1"
  curl -fsS \
    -H "Authorization: Bearer ${OLD_GRAFANA_TOKEN}" \
    -H "Accept: application/json" \
    "${grafana_url%/}${path}"
}

slug() {
  tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

api "/api/search?type=dash-db" > "$output_dir/search.json"
api "/api/folders" > "$output_dir/folders.json"
api "/api/datasources" > "$output_dir/datasources.json"

jq -r '.[] | [.uid, .title] | @tsv' "$output_dir/search.json" |
  while IFS=$'\t' read -r uid title; do
    safe_title="$(printf '%s' "$title" | slug)"
    [ -n "$safe_title" ] || safe_title="$uid"
    api "/api/dashboards/uid/${uid}" > "$output_dir/${safe_title}.${uid}.json"
  done

count="$(find "$output_dir" -maxdepth 1 -name '*.json' ! -name search.json ! -name folders.json ! -name datasources.json | wc -l | tr -d ' ')"
echo "Exported ${count} dashboards to ${output_dir}"
