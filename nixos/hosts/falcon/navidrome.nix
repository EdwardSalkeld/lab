{ config, pkgs, ... }:

let
  domain = "navidrome.alcachofa.faith";
in
{
  security.acme.certs.${domain} = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."acme-cloudflare.env".path;
    group = "nginx";
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = domain;
    locations."/" = {
      # Resolved per request rather than at startup; see webhooks.nix.
      proxyPass = "https://$navidrome_upstream";
      proxyWebsockets = true;
      extraConfig = ''
        resolver 100.100.100.100 valid=60s;
        set $navidrome_upstream kite.ts.alcachofa.faith;
        proxy_buffering off;
        proxy_ssl_name ${domain};
        proxy_ssl_server_name on;
        proxy_ssl_trusted_certificate ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt;
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 2;
      '';
    };
  };
}
