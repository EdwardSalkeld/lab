# The Cloudflare DNS API token, rendered as the environment file that ACME
# certificates using dnsProvider = "cloudflare" point environmentFile at.
{ config, lib, ... }:

{
  options.alcachofa.webTls.cloudflareTokenSopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file holding this host's cloudflare_dns_api_token.";
  };

  config.sops = {
    secrets."acme/cloudflare_dns_api_token" = {
      sopsFile = config.alcachofa.webTls.cloudflareTokenSopsFile;
      key = "cloudflare_dns_api_token";
    };
    templates."acme-cloudflare.env" = {
      mode = "0400";
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder."acme/cloudflare_dns_api_token"}
      '';
    };
  };
}
