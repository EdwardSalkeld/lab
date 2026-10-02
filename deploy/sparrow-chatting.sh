#!/usr/bin/env bash
# Run as root inside sparrow to deploy and smoke-test a Chatting branch.
set -euo pipefail

ref="${1:-roadmap/chatting-upgrades}"
repo=/opt/chatting-roadmap
venv=/opt/chatting-roadmap-venv

apt-get -o Acquire::ForceIPv4=true update
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y \
  ca-certificates git golang-go python3 python3-venv

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

printf 'Deployed Chatting %s to sparrow\n' "$(git -C "$repo" rev-parse HEAD)"
printf 'Handler: %s\n' /usr/local/bin/chatting-test-handler
