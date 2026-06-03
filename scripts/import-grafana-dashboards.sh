#!/usr/bin/env bash
set -euo pipefail

grafana_url="${NEW_GRAFANA_URL:-https://grafana.alcachofa.faith}"
input_dir="${1:-}"

if [ -z "$input_dir" ]; then
  echo "usage: $0 grafana-dashboard-exports/<export-dir>" >&2
  exit 1
fi

if [ -z "${NEW_GRAFANA_TOKEN:-}" ]; then
  echo "NEW_GRAFANA_TOKEN is required" >&2
  exit 1
fi

if [ ! -d "$input_dir" ]; then
  echo "input directory does not exist: $input_dir" >&2
  exit 1
fi

api_get() {
  local path="$1"
  curl -fsS \
    -H "Authorization: Bearer ${NEW_GRAFANA_TOKEN}" \
    -H "Accept: application/json" \
    "${grafana_url%/}${path}"
}

api_post() {
  local path="$1"
  local payload="$2"
  curl -fsS \
    -H "Authorization: Bearer ${NEW_GRAFANA_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    --data-binary "@${payload}" \
    "${grafana_url%/}${path}"
}

if [ -f "$input_dir/folders.json" ]; then
  jq -c '.[]' "$input_dir/folders.json" |
    while read -r folder; do
      uid="$(jq -r '.uid' <<<"$folder")"
      title="$(jq -r '.title' <<<"$folder")"
      if api_get "/api/folders/${uid}" >/dev/null 2>&1; then
        echo "Folder exists: ${title}"
      else
        payload="$(mktemp)"
        jq -n --arg uid "$uid" --arg title "$title" '{uid: $uid, title: $title}' > "$payload"
        api_post "/api/folders" "$payload" >/dev/null
        rm -f "$payload"
        echo "Created folder: ${title}"
      fi
    done
fi

count=0
for dashboard_file in "$input_dir"/*.json; do
  case "$(basename "$dashboard_file")" in
    search.json|folders.json|datasources.json)
      continue
      ;;
  esac

  payload="$(mktemp)"
  jq '
    (.meta.folderUid // "") as $folderUid |
    {
      dashboard: (.dashboard // .),
      overwrite: true
    } +
    (if $folderUid == "" then {} else {folderUid: $folderUid} end) |
    .dashboard.id = null
  ' "$dashboard_file" > "$payload"

  title="$(jq -r '.dashboard.title' "$payload")"
  api_post "/api/dashboards/db" "$payload" >/dev/null
  rm -f "$payload"
  count=$((count + 1))
  echo "Imported dashboard: ${title}"
done

echo "Imported ${count} dashboards from ${input_dir}"
