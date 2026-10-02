#!/usr/bin/env bash
# Install the isolated Chatting test stack on Sparrow.
set -euo pipefail

ref="${1:-prototype/work-item-routing}"
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

install -d -m 700 /etc/chatting /var/lib/chatting /var/lib/chatting/workspaces
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
    'db_path': str(state / 'worker.db'),
    'bbmb_address': '127.0.0.1:9876',
    'codex_command': '/usr/local/bin/codex exec --json --skip-git-repo-check --sandbox danger-full-access',
    'codex_working_dir': str(state),
    'workspace_root': str(state / 'workspaces'),
    'handler_egress_url': 'http://127.0.0.1:9467/egress',
}
for name, value in [('handler.json', handler), ('worker.json', worker)]:
    (config / name).write_text(json.dumps(value, indent=2) + '\n')
    (config / name).chmod(0o600)
PY

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
[Service]
EnvironmentFile=/etc/chatting/secrets.env
ExecStart=/usr/local/bin/chatting-test-handler --config /etc/chatting/handler.json
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
install -m 644 /dev/stdin /etc/systemd/system/chatting-worker.service <<'UNIT'
[Unit]
Description=Chatting test worker
After=chatting-handler.service
Requires=chatting-handler.service
[Service]
Environment=PYTHONPATH=/opt/chatting-roadmap
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
