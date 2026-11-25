# TLS front end for the chatting UIs. The handler shares its port with
# /metrics, so there is no separate vhost for the metrics.
{ config, lib, ... }:

let
  workerDomain = "chatting-worker.int.alcachofa.faith";
  handlerDomain = "chatting-handler.int.alcachofa.faith";
  bbmbDomain = "chatting-bbmb.int.alcachofa.faith";
  platformDomain = "chatting.int.alcachofa.faith";
  hostDomain = "magpie.int.alcachofa.faith";
  hooksDomain = "hooks.alcachofa.faith";
in
{
  imports = [ ../../modules/web-tls.nix ];

  alcachofa.webTls.cloudflareTokenSopsFile = ./secrets/acme-cloudflare.yaml;

  # 80 carries the forceSSL redirect only; DNS-01 never needs it inbound.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "edsalkeld@fastmail.com";
    certs.${workerDomain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-cloudflare.env".path;
      extraDomainNames = [
        handlerDomain
        bbmbDomain
        platformDomain
        hostDomain
        hooksDomain
      ];
      group = "nginx";
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      ${hooksDomain} = {
        forceSSL = true;
        useACMEHost = workerDomain;
        extraConfig = ''
          client_max_body_size 64k;
          client_body_timeout 10s;
          access_log off;
        '';
        locations = {
          "/".return = "404";
        }
        // lib.genAttrs [ "= /webhooks/test" "= /webhooks/github" ] (_: {
          proxyPass = "http://127.0.0.1:9468";
          extraConfig = ''
            if ($request_method != POST) { return 405; }
            proxy_connect_timeout 5s;
            proxy_read_timeout 15s;
            proxy_send_timeout 15s;
            proxy_next_upstream off;
          '';
        });
      };
      ${workerDomain} = {
        forceSSL = true;
        useACMEHost = workerDomain;
        locations."/".proxyPass = "http://127.0.0.1:9465";
        locations."= /internal/secret-file".return = "404";
      };

      ${handlerDomain} = {
        forceSSL = true;
        useACMEHost = workerDomain;
        locations."/".proxyPass = "http://127.0.0.1:9464";
        # Capability URLs are only served via the platform, never logged here.
        locations."^~ /secrets/" = {
          return = "404";
          extraConfig = ''
            access_log off;
            error_log /dev/null crit;
          '';
        };
      };

      # The platform UI has no auth, so only LAN and tailnet clients get in.
      # Its write guard compares Origin with Host, which works because
      # recommendedProxySettings passes Host through.
      ${platformDomain} = {
        forceSSL = true;
        useACMEHost = workerDomain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:9466";
          extraConfig = ''
            allow 10.4.0.0/23;
            allow 100.64.0.0/10;
            allow fd7a:115c:a1e0::/48;
            deny all;
          '';
        };
        locations."^~ /secrets/" = {
          proxyPass = "http://127.0.0.1:9466";
          extraConfig = ''
            allow 10.4.0.0/23;
            allow 100.64.0.0/10;
            allow fd7a:115c:a1e0::/48;
            deny all;
            access_log off;
            error_log /dev/null crit;
          '';
        };
      };

      # Metrics only, no UI. It exists so Prometheus has an HTTPS target and
      # the broker's own port can stay off the network entirely.
      ${bbmbDomain} = {
        forceSSL = true;
        useACMEHost = workerDomain;
        locations."/".proxyPass = "http://127.0.0.1:9877";
      };
    };
  };

  alcachofa.remoteDeploy.postSwitchHealthchecks = [ "nginx.service" ];

  alcachofa.holdingPage = {
    enable = true;
    domains = [ hostDomain ];
    useACMEHost = workerDomain;
    image = ./bird.jpg;
    plate = "Magpie, Pica caudata";
    alt = "A magpie on open ground before a tuft of dry grass, black and white with a long iridescent tail.";
    credit = "Magpie, <i>Pica caudata</i>. Archibald Thorburn, from Lilford's <i>Coloured Figures of the Birds of the British Islands</i> (1885-97). Public domain, via Wikimedia Commons.";
  };
}
