# Family tunnel, stage 1

This stage serves a static hello-world page at `family.salkeld.net` through
Cloudflare Access and a connector running on Partridge. The origin is Python's
static HTTP server on `127.0.0.1:8787`; it is not open on the LAN or Internet.
The Cloudflare tunnel and Access policy live in `site-private/infra/family-tunnel.tf`.

After the site-private PR is merged and Terraform has applied, retrieve the
**sensitive** `family_tunnel_token` output through the protected HCP Terraform
output UI/API. Install it on Partridge at `/var/lib/cloudflared/family-token`,
owned by root and mode 0600. Keep it out of shell history, PRs, logs, and the
Nix store. The unit skips startup until that file exists; after installation,
start `family-tunnel.service` or deploy the host configuration again.

Check `http://127.0.0.1:8787/` on Partridge first. Then verify that an allowed
Edward identity reaches `https://family.salkeld.net/` and that an unlisted
identity cannot pass Access. The two Access applications have separate
allowlists; private-site viewers are not automatically family viewers.

The later Gramps hookup changes the tunnel ingress target from port 8787 to
Gramps Web's local service and deletes `family-tunnel-hello`. Its own LAN
endpoint can be configured in the separate Gramps work item.
