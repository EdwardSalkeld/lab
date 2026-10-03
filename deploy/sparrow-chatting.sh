#!/usr/bin/env bash
# Install the isolated Chatting test stack on Sparrow.
set -euo pipefail

ref="${1:-roadmap/chatting-upgrades}"
repo=/opt/chatting-roadmap
venv=/opt/chatting-roadmap-venv
token=/root/telegram-bot.token

if [[ ! -s "$token" ]]; then
  echo "Place the test bot token in $token before deploying" >&2
  exit 1
fi
chmod 600 "$token"

apt-get -o Acquire::ForceIPv4=true update
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y \
  ca-certificates git golang-go python3 python3-venv curl nodejs npm

if [[ ! -d "$repo/.git" ]]; then
  git clone --no-checkout https://github.com/EdwardSalkeld/chatting.git "$repo"
fi
git -C "$repo" fetch --depth=1 origin "$ref"
git -C "$repo" checkout --detach FETCH_HEAD

python3 -m venv "$venv"
"$venv/bin/pip" install 'croniter>=6.2.2'
PYTHONPATH="$repo" "$venv/bin/python" -c 'import app.main_worker, app.main_reply'
(
  cd "$repo/go/handler"
  go build -o /usr/local/bin/chatting-test-handler ./cmd/chatting-handler
)

if [[ ! -x /usr/local/bin/bbmb-server ]]; then
  curl -fsSL -o /tmp/bbmb-server-linux-amd64 \
    https://github.com/EdwardSalkeld/bbmb/releases/download/v9/bbmb-server-linux-amd64
  curl -fsSL -o /tmp/bbmb-server-linux-amd64.sha256 \
    https://github.com/EdwardSalkeld/bbmb/releases/download/v9/bbmb-server-linux-amd64.sha256
  (cd /tmp && sha256sum -c bbmb-server-linux-amd64.sha256)
  install -m 755 /tmp/bbmb-server-linux-amd64 /usr/local/bin/bbmb-server
  rm -f /tmp/bbmb-server-linux-amd64 /tmp/bbmb-server-linux-amd64.sha256
fi
if ! command -v codex >/dev/null; then
  npm install -g @openai/codex
fi

systemctl stop chatting-worker.service 2>/dev/null || true
install -d -m 700 /etc/chatting /var/lib/chatting
if ! id chatting-worker >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/chatting/worker-home \
    --shell /usr/sbin/nologin chatting-worker
fi
# The handler keeps its own root-owned database and token. The worker needs
# only its database, persistent workspaces, and a private Codex login/home.
chmod 711 /var/lib/chatting
install -d -o chatting-worker -g chatting-worker -m 700 \
  /var/lib/chatting/worker-home /var/lib/chatting/worker-home/.codex \
  /var/lib/chatting/worker-state
if [[ ! -s /var/lib/chatting/worker-home/.codex/auth.json ]]; then
  install -o chatting-worker -g chatting-worker -m 600 \
    /root/.codex/auth.json /var/lib/chatting/worker-home/.codex/auth.json
fi
install -d -o chatting-worker -g chatting-worker -m 700 /var/lib/chatting/workspaces
chown -R chatting-worker:chatting-worker /var/lib/chatting/workspaces
for path in /var/lib/chatting/worker.db /var/lib/chatting/worker.db-*; do
  if [[ -e "$path" ]]; then
    mv "$path" /var/lib/chatting/worker-state/
  fi
done
chown -R chatting-worker:chatting-worker /var/lib/chatting/worker-state
chmod 700 /var/lib/chatting/worker-state
python3 - "$token" <<'PY'
import json
import pathlib
import sys

config = pathlib.Path('/etc/chatting')
state = pathlib.Path('/var/lib/chatting')
secret = pathlib.Path(sys.argv[1]).read_text().strip()
if not secret:
    raise SystemExit('empty Telegram token')
(config / 'secrets.env').write_text('CHATTING_TELEGRAM_BOT_TOKEN=' + secret + '\n')
(config / 'secrets.env').chmod(0o600)
handler = {
    'db_path': str(state / 'handler.db'),
    'bbmb_address': '127.0.0.1:9876',
    'poll_interval_seconds': 2,
    'poll_timeout_seconds': 2,
    'metrics_host': '127.0.0.1',
    'egress_http_host': '127.0.0.1',
    'egress_http_port': 9467,
    'allowed_egress_channels': ['telegram', 'log'],
    'telegram_enabled': True,
    'telegram_bot_token_env': 'CHATTING_TELEGRAM_BOT_TOKEN',
    'telegram_attachment_dir': str(state / 'telegram-attachments'),
}
worker = {
    'db_path': str(state / 'worker-state' / 'worker.db'),
    'bbmb_address': '127.0.0.1:9876',
    'codex_command': '/usr/local/bin/codex exec --json --skip-git-repo-check --sandbox danger-full-access --model gpt-6-luna',
    'codex_working_dir': str(state),
    'workspace_root': str(state / 'workspaces'),
    'handler_egress_url': 'http://127.0.0.1:9467/egress',
}
for name, value in [('handler.json', handler), ('worker.json', worker)]:
    (config / name).write_text(json.dumps(value, indent=2) + '\n')
    (config / name).chmod(0o600)
PY
chmod 711 /etc/chatting
chown chatting-worker:chatting-worker /etc/chatting/worker.json

install -m 644 /dev/stdin /etc/systemd/system/chatting-bbmb.service <<'UNIT'
[Unit]
Description=Chatting test message bus
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/bbmb-server --port=9876 --metrics-port=9877
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
install -m 644 /dev/stdin /etc/systemd/system/chatting-handler.service <<'UNIT'
[Unit]
Description=Chatting test handler
After=chatting-bbmb.service
Requires=chatting-bbmb.service
StartLimitIntervalSec=0
[Service]
EnvironmentFile=/etc/chatting/secrets.env
UMask=0077
ExecStart=/usr/local/bin/chatting-test-handler --config /etc/chatting/handler.json
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
UNIT
install -m 644 /dev/stdin /etc/systemd/system/chatting-worker.service <<'UNIT'
[Unit]
Description=Chatting test worker
After=chatting-handler.service
Wants=chatting-handler.service
[Service]
User=chatting-worker
Group=chatting-worker
Environment=HOME=/var/lib/chatting/worker-home
Environment=CODEX_HOME=/var/lib/chatting/worker-home/.codex
Environment=PYTHONPATH=/opt/chatting-roadmap
UMask=0077
ExecStart=/opt/chatting-roadmap-venv/bin/python -m app.main_worker --config /etc/chatting/worker.json
WorkingDirectory=/opt/chatting-roadmap
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now chatting-bbmb.service chatting-handler.service chatting-worker.service
systemctl restart chatting-bbmb.service chatting-handler.service chatting-worker.service
systemctl is-active chatting-bbmb.service chatting-handler.service chatting-worker.service
printf 'Deployed Chatting %s to sparrow\n' "$(git -C "$repo" rev-parse HEAD)"
