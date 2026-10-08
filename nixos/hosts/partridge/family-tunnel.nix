{ config, pkgs, ... }:

let
  helloWorld = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Family tunnel test</title></head>
      <body><h1>Hello from Partridge</h1><p>The family tunnel is working.</p></body>
    </html>
  '';
in
{
  sops.secrets."family-tunnel/token" = {
    sopsFile = ./secrets/family-tunnel.yaml;
    key = "token";
  };

  # Temporary origin for the first stage. It is only reachable on loopback.
  systemd.services.family-tunnel-hello = {
    description = "Temporary family tunnel hello-world origin";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8787 --bind 127.0.0.1 --directory ${helloWorld}";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" ];
      Restart = "on-failure";
    };
  };

  # SOPS materialises the token outside the Nix store. Pass it through
  # systemd's credential directory to the connector.
  systemd.services.family-tunnel = {
    description = "Cloudflare Tunnel connector for family.salkeld.net";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "family-tunnel-hello.service"
    ];
    wants = [
      "network-online.target"
      "family-tunnel-hello.service"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel run --token-file \${CREDENTIALS_DIRECTORY}/tunnel-token";
      LoadCredential = "tunnel-token:${config.sops.secrets."family-tunnel/token".path}";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
