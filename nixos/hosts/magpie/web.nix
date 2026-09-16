# TLS front end for the chatting UIs. Both already served plain HTTP on the
# LAN: the worker run list on 9465, the handler schedule list on 9464 (which
# also serves /metrics, hence no separate vhost for it).
#
# Before this does anything, Magpie needs its own Cloudflare DNS API token, so
# ACME can solve DNS-01 for the int zone:
#
#   sops nixos/hosts/magpie/secrets/acme-cloudflare.yaml
#
# with a single `cloudflare_dns_api_token` key. Copy the value from another
# host's acme-cloudflare.yaml; the token is shared across the lab. Everything
# below is gated on that file existing, so merging ahead of it is a no-op
# rather than an activation failure (the lab auto-deploys on merge).
{ config, lib, ... }:

let
  acmeSopsFile = ./secrets/acme-cloudflare.yaml;
  tlsEnabled = builtins.pathExists acmeSopsFile;
  workerDomain = "chatting-worker.int.alcachofa.faith";
  handlerDomain = "chatting-handler.int.alcachofa.faith";
in
{
  config = lib.mkIf tlsEnabled {
    sops.secrets."acme/cloudflare_dns_api_token" = {
      sopsFile = acmeSopsFile;
      key = "cloudflare_dns_api_token";
      mode = "0400";
    };

    sops.templates."acme-cloudflare.env" = {
      mode = "0400";
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder."acme/cloudflare_dns_api_token"}
      '';
    };

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
        extraDomainNames = [ handlerDomain ];
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
        ${workerDomain} = {
          forceSSL = true;
          useACMEHost = workerDomain;
          locations."/".proxyPass = "http://127.0.0.1:9465";
        };

        ${handlerDomain} = {
          forceSSL = true;
          useACMEHost = workerDomain;
          locations."/".proxyPass = "http://127.0.0.1:9464";
        };
      };
    };

    alcachofa.remoteDeploy.postSwitchHealthchecks = [ "nginx.service" ];
  };
}
