{
  config,
  pkgs,
  lib,
  ...
}:

let
  domain = "hooks.alcachofa.faith";
in
{
  security.acme.certs.${domain} = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."acme-cloudflare.env".path;
    group = "nginx";
  };

  # A global budget also bounds log volume when traffic comes from many IPs.
  services.nginx.appendHttpConfig = ''
    limit_req_zone $server_name zone=webhook_ingress:1m rate=10r/s;
  '';
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = domain;
    extraConfig = ''
      client_max_body_size 64k;
      client_body_timeout 10s;
      client_header_timeout 10s;
      limit_req_status 429;
      access_log off;
    '';
    locations = {
      "/".return = "404";
    }
    // lib.genAttrs [ "= /webhooks/test" "= /webhooks/github" ] (_: {
      # A variable defers the lookup to request time. A literal hostname is
      # resolved when nginx starts, which fails while a switch is restarting
      # tailscaled and takes nginx (and the switch) down with it.
      proxyPass = "https://$webhooks_upstream";
      extraConfig = ''
        resolver 100.100.100.100 valid=60s;
        set $webhooks_upstream magpie.ts.alcachofa.faith;
        if ($request_method != POST) { return 405; }
        limit_req zone=webhook_ingress burst=20 nodelay;
        proxy_ssl_name ${domain};
        proxy_ssl_server_name on;
        proxy_ssl_trusted_certificate ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt;
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 2;
        proxy_connect_timeout 5s;
        proxy_read_timeout 15s;
        proxy_send_timeout 15s;
        proxy_next_upstream off;
      '';
    });
  };
}
