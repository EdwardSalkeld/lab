# Family tunnel, stage 1

This stage serves a static hello-world page at `family.salkeld.net` through
Cloudflare Access and a connector running on Partridge. The origin is Python's
static HTTP server on `127.0.0.1:8787`; it is not open on the LAN or Internet.
The Cloudflare tunnel and Access policy live in `site-private/infra/family-tunnel.tf`.

The connector token comes from the sensitive HCP Terraform
`family_tunnel_token` output. It is encrypted in
`nixos/hosts/partridge/secrets/family-tunnel.yaml` and deployed by SOPS with
the rest of Partridge's secrets. The service reads the decrypted file through
systemd credentials; the token never enters the Nix store.

After deploying lab, check `http://127.0.0.1:8787/` on Partridge first. Then
verify that an allowed Edward identity reaches `https://family.salkeld.net/`
and that an unlisted identity cannot pass Access. The two Access applications have separate
allowlists; private-site viewers are not automatically family viewers.

The later Gramps hookup changes the tunnel ingress target from port 8787 to
Gramps Web's local service and deletes `family-tunnel-hello`. Its own LAN
endpoint can be configured in the separate Gramps work item.
