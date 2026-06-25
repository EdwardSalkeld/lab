{ config, pkgs, ... }:

let
  user = "opnsense-exporter";
  group = user;
  exporter = pkgs.callPackage ./pkgs/opnsense-exporter.nix { };
  listenAddr = "127.0.0.1:8080";
  opnsenseAddress = "10.4.1.1";
in
{
  sops.secrets."opnsense-exporter/api_key" = {
    sopsFile = ./secrets/opnsense-exporter.yaml;
    key = "api_key";
    owner = user;
    inherit group;
  };
  sops.secrets."opnsense-exporter/api_secret" = {
    sopsFile = ./secrets/opnsense-exporter.yaml;
    key = "api_secret";
    owner = user;
    inherit group;
  };

  sops.templates."opnsense-exporter.env" = {
    owner = user;
    inherit group;
    mode = "0400";
    content = ''
      OPNSENSE_EXPORTER_OPS_API_KEY=${config.sops.placeholder."opnsense-exporter/api_key"}
      OPNSENSE_EXPORTER_OPS_API_SECRET=${config.sops.placeholder."opnsense-exporter/api_secret"}
    '';
  };

  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };

  systemd.services.opnsense-exporter = {
    description = "Prometheus exporter for OPNsense";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      OPNSENSE_EXPORTER_OPS_API = opnsenseAddress;
      OPNSENSE_EXPORTER_OPS_PROTOCOL = "https";
      # OPNsense serves its API behind a self-signed cert.
      OPNSENSE_EXPORTER_OPS_INSECURE = "true";
      OPNSENSE_EXPORTER_INSTANCE_LABEL = "opnsense";
    };
    serviceConfig = {
      User = user;
      Group = group;
      EnvironmentFile = config.sops.templates."opnsense-exporter.env".path;
      # Disable collectors for services not running here (avoids noisy errors).
      ExecStart = "${exporter}/bin/opnsense-exporter --web.listen-address=${listenAddr} --exporter.disable-wireguard --exporter.disable-ipsec --exporter.disable-openvpn --exporter.disable-unbound";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };
}
