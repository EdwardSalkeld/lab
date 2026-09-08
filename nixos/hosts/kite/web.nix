{ config, ... }:

let
  jellyfinDomain = "jellyfin.alcachofa.faith";
  navidromeDomain = "navidrome.alcachofa.faith";
  wantlistDomain = "wantlist.alcachofa.faith";
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

  # Do not trust the whole Tailnet interface: both applications must be reached
  # through Nginx, whether the client is on the LAN or reaches Kite via Falcon.
  networking.firewall.interfaces = {
    ens18.allowedTCPPorts = [
      22
      80
      443
      9100
    ];
    tailscale0.allowedTCPPorts = [
      22
      443
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "edsalkeld@fastmail.com";
    certs.${jellyfinDomain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-cloudflare.env".path;
      extraDomainNames = [
        navidromeDomain
        wantlistDomain
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
      ${jellyfinDomain} = {
        forceSSL = true;
        useACMEHost = jellyfinDomain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
        };
      };

      ${navidromeDomain} = {
        forceSSL = true;
        useACMEHost = jellyfinDomain;
        locations."/".proxyPass = "http://127.0.0.1:4533";
      };

      ${wantlistDomain} = {
        forceSSL = true;
        useACMEHost = jellyfinDomain;
        locations."/".proxyPass = "http://127.0.0.1:8000";
      };
    };
  };
}
