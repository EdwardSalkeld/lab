# Sparrow: Chatting roadmap test container

`sparrow` is a Debian 13 LXC on Proxmox `sol`, managed by
`terraform/proxmox_virtual_environment_container.sparrow` (CT 76300). It has
4 CPU cores, 4 GiB RAM, a 24 GiB root disk on `local-lvm`, and DHCP on `vmbr0`.
It is unprivileged on the Proxmox host. Edward and Billy have key-based SSH as
root inside the container, with no sudo restrictions in the guest.

The container is a separate test target. It has no production Chatting state.
Its test Telegram bot token is placed in `/root/telegram-bot.token` on Sparrow;
the deploy script copies it into a root-only service environment file. The test
stack has Telegram and log egress only, with no email or GitHub polling.

From the Lab checkout, run `deploy/sparrow-chatting.sh` as root with the desired
ref, for example:

```sh
ssh root@sparrow.int.alcachofa.faith bash -s -- prototype/work-item-routing < deploy/sparrow-chatting.sh
```

Billy can use the versioned Lab SSH helper and its pinned host key from the
workspace root:

```sh
python3 memory/skills/lab-direct-ssh/scripts/lab_ssh.py root@sparrow.int.alcachofa.faith -- bash -s -- prototype/work-item-routing < lab/deploy/sparrow-chatting.sh
```

The script is idempotent and prints the deployed commit. It installs and starts
`chatting-bbmb`, `chatting-handler`, and `chatting-worker` as systemd services.
Its checkout lives at `/opt/chatting-roadmap`; the Python environment is
`/opt/chatting-roadmap-venv`; handler and worker state is under
`/var/lib/chatting`. It installs Codex separately. Codex needs root-only login
state in `/root/.codex` or an API key in the root service environment before
the worker can answer tasks. Authentication state is kept off Git.
The test bot's Telegram handle can be checked using `getMe`. Check service
status with `systemctl status chatting-bbmb chatting-handler chatting-worker`.
`pct exec 76300 -- ...` on `sol` is available for recovery if guest SSH is
unavailable.
