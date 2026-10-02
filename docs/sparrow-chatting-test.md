# Sparrow: Chatting roadmap test container

`sparrow` is a Debian 13 LXC on Proxmox `sol`, managed by
`terraform/proxmox_virtual_environment_container.sparrow` (CT 76300). It has
4 CPU cores, 4 GiB RAM, a 24 GiB root disk on `local-lvm`, and DHCP on `vmbr0`.
It is unprivileged on the Proxmox host. Edward and Billy have key-based SSH as
root inside the container, with no sudo restrictions in the guest.

The container is a separate test target. It has no production Chatting state or
Telegram credentials. The current deployment check installs a chosen Chatting
ref, imports the Python worker entrypoints, and builds the Go handler. It does
not start services or consume production ingress. Add separate test credentials
and routing before running a handler against Telegram or email.

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

The script is idempotent and prints the deployed commit. Its checkout lives at
`/opt/chatting-roadmap`; the Python environment is
`/opt/chatting-roadmap-venv`; the handler binary is
`/usr/local/bin/chatting-test-handler`. The command above is the deployment
smoke test. `pct exec 76300 -- ...` on `sol` is available for recovery if SSH
to the guest is unavailable.
