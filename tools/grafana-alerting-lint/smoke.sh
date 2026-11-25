#!/usr/bin/env bash
# Start Grafana against a provisioning directory and wait until every rule,
# contact point, template, policy, datasource and dashboard it holds is loaded.
# Grafana provisions alerting in the background after the HTTP server is up, so
# a healthy /api/health alone does not prove provisioning finished.
#
# usage: smoke.sh <grafana-package> <provisioning-dir> <work-dir>
set -euo pipefail
export LC_ALL=C

grafana="$1"
provisioning="$2"
work="$3"
port="${GRAFANA_SMOKE_PORT:-3000}"
deadline_seconds="${GRAFANA_SMOKE_TIMEOUT:-180}"
base="http://127.0.0.1:$port"

mkdir -p "$work/data" "$work/logs" "$work/plugins"
export GF_PATHS_PROVISIONING="$provisioning"
export GF_PATHS_DATA="$work/data"
export GF_PATHS_LOGS="$work/logs"
export GF_PATHS_PLUGINS="$work/plugins"
export GF_SERVER_HTTP_ADDR=127.0.0.1
export GF_SERVER_HTTP_PORT="$port"
export GF_SECURITY_ADMIN_USER=admin
export GF_SECURITY_ADMIN_PASSWORD=admin
export GF_ANALYTICS_REPORTING_ENABLED=false
export GF_ANALYTICS_CHECK_FOR_UPDATES=false
export GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false
export GRAFANA_TELEGRAM_BOT_TOKEN="${GRAFANA_TELEGRAM_BOT_TOKEN:-dummy}"

"$grafana/bin/grafana" server \
  --homepath "$grafana/share/grafana" \
  --config "$grafana/share/grafana/conf/defaults.ini" \
  >"$work/grafana.log" 2>&1 &
grafana_pid=$!

stop_grafana() {
  if kill -0 "$grafana_pid" 2>/dev/null; then
    kill "$grafana_pid"
    wait "$grafana_pid" || true
  fi
}
trap stop_grafana EXIT

fail() {
  echo "grafana smoke: $*" >&2
  echo "--- grafana log ---" >&2
  cat "$work/grafana.log" >&2
  exit 1
}

api() {
  curl --silent --show-error --fail --user admin:admin "$base$1"
}

# Expected objects, read from the same files Grafana provisions.
yaml_files() {
  find "$provisioning/$1" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \)
}
sorted() { sort -u | sed '/^$/d'; }

mapfile -t alerting_files < <(yaml_files alerting)
mapfile -t datasource_files < <(yaml_files datasources)
mapfile -t dashboard_provider_files < <(yaml_files dashboards)

expected_rules="$(jq -r '.groups[]?.rules[]?.uid' "${alerting_files[@]}" | sorted)"
expected_contact_points="$(jq -r '.contactPoints[]?.name' "${alerting_files[@]}" | sorted)"
expected_templates="$(jq -r '.templates[]?.name' "${alerting_files[@]}" | sorted)"
expected_policy_receiver="$(jq -r '.policies[]?.receiver' "${alerting_files[@]}" | sorted)"
expected_datasources="$(jq -r '.datasources[]?.uid' "${datasource_files[@]}" | sorted)"
mapfile -t dashboard_dirs < <(jq -r '.providers[]?.options.path' "${dashboard_provider_files[@]}")
expected_dashboards="$(
  find "${dashboard_dirs[@]}" -type f -name '*.json' -print0 \
    | xargs -0 --no-run-if-empty jq -r '.uid' | sorted
)"

[ -n "$expected_rules" ] || fail "no alert rules found under $provisioning/alerting"
[ -n "$expected_datasources" ] || fail "no datasources found under $provisioning/datasources"

missing() {
  # Lines of $1 that are not in $2.
  comm -23 <(printf '%s\n' "$1" | sorted) <(printf '%s\n' "$2" | sorted)
}

check_loaded() {
  local got
  got="$(api /api/v1/provisioning/alert-rules | jq -r '.[].uid' | sorted)" || return 1
  [ -z "$(missing "$expected_rules" "$got")" ] || {
    pending="alert rules: $(missing "$expected_rules" "$got" | tr '\n' ' ')"
    return 1
  }
  got="$(api /api/v1/provisioning/contact-points | jq -r '.[].name' | sorted)" || return 1
  [ -z "$(missing "$expected_contact_points" "$got")" ] || {
    pending="contact points: $(missing "$expected_contact_points" "$got" | tr '\n' ' ')"
    return 1
  }
  got="$(api /api/v1/provisioning/templates | jq -r '.[].name' | sorted)" || return 1
  [ -z "$(missing "$expected_templates" "$got")" ] || {
    pending="templates: $(missing "$expected_templates" "$got" | tr '\n' ' ')"
    return 1
  }
  got="$(api /api/v1/provisioning/policies | jq -r '.receiver' | sorted)" || return 1
  [ -z "$(missing "$expected_policy_receiver" "$got")" ] || {
    pending="notification policy receiver: wanted $expected_policy_receiver, got $got"
    return 1
  }
  got="$(api /api/datasources | jq -r '.[].uid' | sorted)" || return 1
  [ -z "$(missing "$expected_datasources" "$got")" ] || {
    pending="datasources: $(missing "$expected_datasources" "$got" | tr '\n' ' ')"
    return 1
  }
  got="$(api '/api/search?type=dash-db&limit=5000' | jq -r '.[].uid' | sorted)" || return 1
  [ -z "$(missing "$expected_dashboards" "$got")" ] || {
    pending="dashboards: $(missing "$expected_dashboards" "$got" | tr '\n' ' ')"
    return 1
  }
}

pending="Grafana health"
start="$(date +%s)"
while :; do
  kill -0 "$grafana_pid" 2>/dev/null || fail "Grafana exited before provisioning finished (waiting for $pending)"
  if (($(date +%s) - start > deadline_seconds)); then
    fail "timed out after ${deadline_seconds}s waiting for $pending"
  fi
  if curl --silent --fail "$base/api/health" >/dev/null 2>&1; then
    pending="provisioning"
    if check_loaded; then
      break
    fi
  fi
  sleep 1
done

if grep -E 'level=(error|crit)' "$work/grafana.log" | grep -Ei 'provision'; then
  fail "Grafana logged provisioning errors"
fi

echo "grafana smoke: provisioned $(wc -l <<<"$expected_rules") rules, $(wc -l <<<"$expected_datasources") datasources and $(wc -l <<<"$expected_dashboards") dashboards"
