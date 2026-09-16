# TLS front end for the chatting UIs. Both had only ever been plain HTTP on the
# LAN, relying on being LAN-only: the worker run list on 9465, and the handler
# schedule list on 9464. The handler shares its port with /metrics, so there is
# no separate vhost for the metrics.
{ config, ... }:

let
  workerDomain = "chatting-worker.int.alcachofa.faith";
  handlerDomain = "chatting-handler.int.alcachofa.faith";
in
{
  sops.secrets."acme/cloudflare_dns_api_token" = {
    sopsFile = ./secrets/acme-cloudflare.yaml;
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
}
