# TLS front end for the chatting UIs. The handler shares its port with
# /metrics, so there is no separate vhost for the metrics.
{ config, ... }:

let
  workerDomain = "chatting-worker.int.alcachofa.faith";
  handlerDomain = "chatting-handler.int.alcachofa.faith";
  bbmbDomain = "chatting-bbmb.int.alcachofa.faith";
  hostDomain = "magpie.int.alcachofa.faith";
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
      extraDomainNames = [
        handlerDomain
        bbmbDomain
        hostDomain
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
