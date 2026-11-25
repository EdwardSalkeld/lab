{ config, ... }:

let
  partridgeInternalDomain = "partridge.int.alcachofa.faith";
  partridgeTailnetDomain = "partridge.ts.alcachofa.faith";
in
{
  imports = [ ../../modules/web-tls.nix ];

  alcachofa.webTls.cloudflareTokenSopsFile = ./secrets/acme-cloudflare.yaml;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    acceptTerms = true;
    certs.${partridgeInternalDomain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-cloudflare.env".path;
      extraDomainNames = [ partridgeTailnetDomain ];
      group = "nginx";
    };
    defaults.email = "edsalkeld@fastmail.com";
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
  };

  alcachofa.holdingPage = {
    enable = true;
    domains = [
      partridgeInternalDomain
      partridgeTailnetDomain
    ];
    useACMEHost = partridgeInternalDomain;
    image = ./bird.jpg;
    plate = "Common or Grey Partridge, Perdix cinerea";
    alt = "A grey partridge standing among daisies and dry grass, a second bird crouched behind it.";
    credit = "Common or Grey Partridge, <i>Perdix cinerea</i>. Drawn by E. Neale, lithographed by J. Smit, from Lilford's <i>Coloured Figures of the Birds of the British Islands</i> (1885-97). CC BY 2.0, via Wikimedia Commons.";
  };
}
