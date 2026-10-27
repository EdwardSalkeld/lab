# Zulip on Luna

## Shape

Terraform creates `zulip-vm`, a persistent Debian 13 guest on Luna: 2 vCPUs,
3 GiB RAM, 40 GiB root disk and DHCP on `vmbr0`. The application bootstrap adds
2 GiB swap. Debian's cloud image and Zulip 12.3 are pinned and checksum-checked.
This guest is intentionally outside the NixOS closure deployment loop.

Zulip's PostgreSQL 17 database lives on **Partridge**. Its existing
`postgresqlBackup` (`backupAll = true`) and `partridge-postgres` Restic/B2 job
include the new database automatically. No Zulip-specific backup timer,
tar archive or upload backup is introduced.

Settings and service config live in `services/zulip/`; stable secrets live in
`nixos/hosts/partridge/secrets/zulip.yaml`, SOPS-encrypted to the same recovery
recipients as the other Partridge secrets. Partridge renders an application
secrets file, including the existing Fastmail SMTP app credential. Preserve
these keys during recovery rather than letting the app generate new identities.

Uploads remain local to the guest at `/home/zulip/uploads`. They are explicitly
disposable: losing the app VM loses attachments, avatars and custom emoji,
including any referenced by restored messages. Messages and user/channel data
are in the backed-up database. Redis/Memcached are transient; RabbitMQ may have
in-flight jobs, so DB-only recovery can also lose pending notifications.

## Rollout

1. Review Terraform's plan and current Luna capacity. The 2026-10-27 snapshot
   had about 5.3 GiB available host RAM and 113 GiB physical thin-pool space;
   allow headroom for Kite. Applying creates a guest; it does not install Zulip.
   The VM is protected against Terraform destroy/replacement.
2. Deploy Partridge's NixOS configuration. This creates a `zulip` login and
   `C.UTF-8` database, renders stable secrets, and adds the HTTPS proxy. Database
   creation is conditional and never drops an existing database. Check:

   ```sh
   ssh billy@partridge sudo systemctl status zulip-db-setup
   ssh billy@partridge sudo -u postgres psql -d zulip -Atc 'SELECT current_database()'
   ```

3. Inspect the new guest's DHCP lease/console and pin its SSH host key using
   the normal Lab procedure. Make `zulip-vm.int.alcachofa.faith` resolve to the
   guest (reserve the DHCP lease), and add `zulip.int.alcachofa.faith` as a DNS
   alias/override to Partridge (`10.4.1.30`). DNS is currently an OPNsense
   operational step, as for other LAN services, not Terraform-managed here.
   The proxy resolves its upstream lazily so a missing guest/DNS record affects
   only Zulip, rather than preventing nginx from starting.
4. From a trusted admin checkout with SSH access to both hosts, stage exactly
   the reviewed Lab commit and credentials. Keep shell tracing off:

   ```sh
   ssh billy@zulip-vm sudo install -d -o billy -g billy /opt/lab
   git archive HEAD | ssh billy@zulip-vm tar -x -C /opt/lab
   ssh billy@partridge sudo cat /run/secrets/rendered/zulip-secrets.conf \
     | ssh billy@zulip-vm 'sudo sh -c "umask 077; cat > /run/zulip-secrets.conf"'
   ssh billy@zulip-vm sudo bash /opt/lab/scripts/zulip-bootstrap.sh /run/zulip-secrets.conf
   ```

   The cloud image must finish `cloud-init status --wait` before this step.
   The script installs the guest-agent package, dependencies, app and guest firewall;
   initializes/migrates the remote database; then deletes the staged secret.
   The configuration is generated from the pinned upstream production template
   plus versioned overrides, and can be reapplied at the same pinned release.
   The agent channel is initially disabled in Terraform to avoid first-boot
   waits; it can be enabled in a follow-up VM configuration once bootstrapped.
5. Generate a single-use organization creation link for Edward:

   ```sh
   ssh billy@zulip-vm sudo su zulip -c \
     '/home/zulip/deployments/current/manage.py generate_realm_creation_link'
   ```

   Use it at `https://zulip.int.alcachofa.faith`, choose invite-only signup,
   and verify login, message delivery, search, upload handling and outgoing
   email. The site is LAN/Tailscale-only through Partridge; no WAN forwarding.
   Guest HTTP accepts only Partridge; internal queues/caches are not exposed.
   HTTPS and certificate renewal reuse Partridge's existing ACME setup.
6. Confirm the next `postgresqlBackup` and Restic runs include `zulip`.
   The initial rollout should rehearse database restoration into an isolated
   test database/guest before treating it as recoverable. Do not restore over
   production to perform that check.

## Reapply, upgrade and recover

For config edits at the same release, repeat staging and bootstrap. For an
application release upgrade, update `release.env` and its SHA256, read Zulip's
release notes, take/confirm a database backup, use the upstream `upgrade-zulip`
tool on the guest, then reapply the reviewed configuration. The bootstrap
refuses to silently upgrade an existing different release.

Recovery: deploy the matching PostgreSQL major on Partridge, restore its normal
database dump (including the role/password through the repo-managed setup),
rebuild the Debian guest, and reapply the same Zulip release, settings and SOPS
secrets. The bootstrap's migrate step is safe for an already populated database;
it does not invoke Zulip's destructive `create-db.sql`. Uploads are not recovered.
No organization creation step is needed for an existing restored organization.

The shared database uses built-in English stemming as in Zulip's managed-DB
deployment path; its application-side `process_fts_updates` handles search
index updates. We do not run Zulip's Debian PostgreSQL installer on NixOS.
Postgres access follows existing LAN clients (SCRAM authentication without
transport TLS). Partridge's DB role is not a superuser.

SMTP reuses the existing Fastmail login with `billy@alcachofa.faith` sender and
plus-addressed token senders. Verify delivery before sending invitations.
Official mobile push is disabled until relay registration is deliberately set
up; this has no effect on browser chat. Monitor both app and shared DB disk
usage: the Partridge DB disk had about 4.4 GiB available during research.

Upstream references:
- [External PostgreSQL](https://zulip.readthedocs.io/en/stable/production/postgresql.html)
- [Proxy configuration](https://zulip.readthedocs.io/en/stable/production/reverse-proxies.html)
- [Database backup and restore](https://zulip.readthedocs.io/en/stable/production/export-and-import.html)
