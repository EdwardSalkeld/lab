{ pkgs, ... }:

let
  partridgeInternalDomain = "partridge.int.alcachofa.faith";
  partridgeTailnetDomain = "partridge.ts.alcachofa.faith";
  partridgeSite = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>partridge</title>
        <style>
          :root {
            color-scheme: light dark;
            font-family: ui-sans-serif, system-ui, sans-serif;
          }

          body {
            align-items: center;
            display: grid;
            margin: 0;
            min-height: 100vh;
            place-items: center;
          }

          main {
            max-width: 34rem;
            padding: 2rem;
          }

          h1 {
            font-size: 2.5rem;
            font-weight: 700;
            letter-spacing: 0;
            margin: 0 0 0.75rem;
          }

          p {
            line-height: 1.6;
            margin: 0;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>partridge</h1>
          <p>NixOS on Proxmox, managed from the lab IaC repo.</p>
        </main>
      </body>
    </html>
  '';
in
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    acceptTerms = true;
    certs.${partridgeInternalDomain} = {
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/secrets/acme-cloudflare.env";
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

    virtualHosts = {
      ${partridgeInternalDomain} = {
        forceSSL = true;
        root = partridgeSite;
        useACMEHost = partridgeInternalDomain;
      };

      ${partridgeTailnetDomain} = {
        forceSSL = true;
        root = partridgeSite;
        useACMEHost = partridgeInternalDomain;
      };
    };
  };
}
