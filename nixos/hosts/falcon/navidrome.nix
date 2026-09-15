{ config, pkgs, ... }:

let
  domain = "navidrome.alcachofa.faith";
in
{
  sops = {
    defaultSopsFile = ./secrets/acme-cloudflare.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets."acme/cloudflare_dns_api_token".key = "cloudflare_dns_api_token";
    templates."acme-cloudflare.env" = {
      mode = "0400";
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder."acme/cloudflare_dns_api_token"}
      '';
    };
  };

  security.acme.certs.${domain} = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."acme-cloudflare.env".path;
    group = "nginx";
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = domain;
    locations."/" = {
      proxyPass = "https://kite.ts.alcachofa.faith";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_ssl_name ${domain};
        proxy_ssl_server_name on;
        proxy_ssl_trusted_certificate ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt;
        proxy_ssl_verify on;
      '';
    };
  };
}
