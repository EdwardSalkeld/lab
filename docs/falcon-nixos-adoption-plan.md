# Falcon NixOS Adoption Plan

Falcon is a small bare-metal Debian host.  It is not part of the Proxmox
estate, so its NixOS configuration should live in this repository as a
dedicated bare-metal target, rather than inherit the VM base module.

The aim is a boring, reversible migration: retain Falcon's network identity
and useful services, make the operating system declarative, and avoid moving
unrelated workloads to other hosts.

## Repository inventory

The only active Falcon configuration in `house` is
`falcon/docker/docker-compose.yml`, plus Traefik and Alloy configuration.
It declares the following workloads:

| Workload | Current role | Initial disposition |
| --- | --- | --- |
| Tailscale (host) | Remote access and the Tailnet exit node | Keep, including exit-node advertising and current identity where practical |
| SSH (host) | Administration | Keep |
| Traefik | TLS reverse proxy for `falcon.alcachofa.faith` and its wildcard subdomain | Keep |
| FreshRSS | The only declared application with persistent state | Keep |
| Alloy | Ships host and Docker logs to Loki on Partridge | Keep, correct its `host = "fourth"` label to `falcon` |
| node_exporter | Host metrics for Prometheus on Partridge | Keep, use the NixOS exporter |
| cAdvisor | Docker/container metrics for Prometheus on Partridge | Keep only while Docker workloads remain |
| whoami | Traefik smoke/test service | Drop after an equivalent proxy health check exists |

The Compose file also references a Cloudflare DNS API token, an ACME state
file below `falcon/docker/data/`, and two named FreshRSS volumes.  These are
state/secrets to preserve, not values to copy into Nix source.

Observability already assumes Falcon remains a separate host: Partridge
scrapes `falcon.ts.alcachofa.faith:8080` for cAdvisor and `:9100` for node
metrics.  The local configuration binds cAdvisor, Traefik's dashboard, and
Alloy's HTTP port to Falcon's current Tailnet address.

## Decisions to make before implementation

1. Confirm the live container list, enabled host services, disk layout, and
   real FreshRSS data location. The House repository is a useful baseline but
   is not proof of the running machine.
2. Decide whether the existing NixOS installation should retain its current
   Tailscale machine identity and SSH host keys. Keeping both makes the
   cutover quieter; neither is a reason to avoid the migration.
3. Choose the proxy shape for the first cutover:
   - native NixOS Traefik/FreshRSS if their required settings fit cleanly; or
   - NixOS-managed Docker/Compose for Traefik and FreshRSS, followed by a
     separate native-service conversion.

   The first option is preferable only if it preserves the existing DNS-01
   certificate flow and FreshRSS state without a bespoke workaround.
4. Record the public routes that really matter. The Compose default rule
   implies `freshrss.falcon.alcachofa.faith`; this needs a live check before
   treating it as a contract.

## Implementation phases

### 1. Capture and back up

- SSH to Falcon and collect `systemctl`, `docker ps`, `docker volume ls`,
  `lsblk -f`, `findmnt`, listening ports, Tailscale status, firewall settings,
  and the active checkout/Compose command.
- Back up the FreshRSS volumes, Traefik ACME state, and any configuration or
  secret files that are live but absent from Git. Verify a FreshRSS restore in
  an isolated temporary location before changing the host.
- Save the relevant SSH host keys and Tailscale state if we choose to retain
  those identities. Take a normal host backup/snapshot appropriate to its
  storage before reinstalling.

### 2. Add the Lab configuration and prove it builds

- Add `nixos/hosts/falcon/configuration.nix` and a generated
  `hardware-configuration.nix`; add `.#falcon` to the flake. Do not import
  `proxmox-vm-base.nix`.
- Declare the base host: UEFI boot, stable mounts, SSH, Tailscale, firewall,
  automatic Nix garbage collection, the `edward` and dedicated `billy`
  accounts, and node_exporter.
- Declare the exit-node behaviour explicitly: IP forwarding and the
  Tailscale advertised exit route. Preserve the current public/Tailnet
  firewall surface deliberately rather than accidentally opening every app.
- Add Alloy as a native NixOS service. It must keep Docker log discovery for
  as long as Docker remains, point at Partridge Loki, and label logs
  `host = "falcon"`.
- Keep cAdvisor during the compatibility phase and retain the existing
  Prometheus scrape endpoints. Update Partridge only if the chosen bindings
  change.
- Build `nix build .#nixosConfigurations.falcon.config.system.build.toplevel`
  in CI before any host work.

### 3. Prepare a compatibility cutover

- Use a fresh NixOS installation on Falcon's OS disk while leaving application
  data intact, unless the live disk review makes an in-place conversion clearly
  safer.
- First boot only the base host: network, SSH, Tailscale/exit node, mounts,
  node_exporter, and Alloy. Confirm remote access, exit-node traffic, metrics,
  and Loki ingestion before starting the proxy or application.
- Restore FreshRSS and Traefik state. Initially it is acceptable to run the
  existing two containers under NixOS-managed Docker/Compose; their image
  versions must be pinned rather than left as `latest` or `:1`.
- Validate TLS/DNS-01 renewal, the real FreshRSS hostname and login/data,
  Traefik dashboard access from the Tailnet only, and Prometheus targets.

### 4. Simplify after the cutover

- Move FreshRSS and Traefik to native NixOS services only when the restored
  compatibility setup is stable. Retire Docker, cAdvisor, and Docker log
  discovery together once no Docker workload remains.
- Replace `whoami` with a small explicit health check, or remove it entirely.
- Move the Cloudflare API token into SOPS-managed Falcon secrets; do not put
  the token or ACME account material in Git.
- Tighten firewall and dashboard exposure based on the confirmed consumers.

## Cutover acceptance checks

- SSH works for Edward and Billy; the host is reachable over its expected
  Tailnet name.
- Falcon still functions as the exit node.
- `https://freshrss.falcon.alcachofa.faith` (or its confirmed route) serves
  the restored FreshRSS data with a valid certificate.
- Partridge sees healthy Falcon node metrics, cAdvisor metrics during the
  Docker phase, and Loki logs labelled `host="falcon"`.
- A reboot preserves mounts, services, certificates, and FreshRSS data.

## Non-goals for the first change

- Moving Falcon services onto Partridge, Kite, or another host.
- Replacing the exit-node role.
- Rebuilding the application or changing FreshRSS data.
- Treating the current House Compose file as proof of runtime state.

## References

- House source: `falcon/docker/docker-compose.yml`, `traefik.conf`, and
  `alloy.conf`
- Partridge monitoring: `nixos/hosts/partridge/prometheus.nix`
- Partridge Loki endpoint: `nixos/hosts/partridge/loki.nix`
- Similar bare-metal planning reference (historical Blink work):
  `docs/blink-nixos-adoption-plan.md` in earlier Lab history
