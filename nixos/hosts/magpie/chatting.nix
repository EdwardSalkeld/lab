{ pkgs, chattingRuntimePackage, ... }:

let
  handlerConfigPath = "/etc/chatting/handler.json";
  workerConfigPath = "/etc/chatting/worker.json";
  bbmbBin = "${chattingRuntimePackage}/bin/bbmb-server";
  handlerBin = "${chattingRuntimePackage}/bin/chatting-handler";
  workerBin = "${chattingRuntimePackage}/bin/chatting-worker";
in
{
  systemd.targets.chatting = {
    description = "Chatting split runtime";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.chatting-bbmb = {
    description = "Chatting BBMB broker";
    wantedBy = [ "chatting.target" ];
    partOf = [ "chatting.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.bash ];
    serviceConfig = {
      Type = "simple";
      User = "bbmb";
      Group = "bbmb";
      Environment = [ "CHATTING_CONFIG_DIR=/etc/chatting" ];
      ExecStart = "${bbmbBin} --port=9876 --metrics-port=9877";
      WorkingDirectory = "/var/lib/bbmb";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/bbmb" ];
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
    };
  };

  systemd.services.chatting-handler = {
    description = "Chatting message handler";
    wantedBy = [ "chatting.target" ];
    partOf = [ "chatting.target" ];
    after = [
      "network-online.target"
      "chatting-bbmb.service"
    ];
    wants = [
      "network-online.target"
      "chatting-bbmb.service"
    ];
    requires = [ "chatting-bbmb.service" ];
    unitConfig.ConditionPathExists = [ handlerConfigPath ];
    path = [
      pkgs.bash
      pkgs.cacert
      pkgs.gh
      pkgs.git
    ];
    serviceConfig = {
      Type = "simple";
      User = "handler";
      Group = "handler";
      Environment = [
        "HOME=/var/lib/handler"
        "CHATTING_CONFIG_DIR=/etc/chatting"
      ];
      EnvironmentFile = "-/etc/chatting/handler.env";
      ExecStart = "${handlerBin} --config ${handlerConfigPath}";
      WorkingDirectory = "/var/lib/handler";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ handlerConfigPath ];
      ReadWritePaths = [ "/var/lib/handler" ];
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
    };
  };

  systemd.services.chatting-worker = {
    description = "Chatting worker";
    wantedBy = [ "chatting.target" ];
    partOf = [ "chatting.target" ];
    after = [
      "network-online.target"
      "chatting-bbmb.service"
    ];
    wants = [
      "network-online.target"
      "chatting-bbmb.service"
    ];
    requires = [ "chatting-bbmb.service" ];
    unitConfig.ConditionPathExists = [
      workerConfigPath
      "/srv/chatting/workspace"
    ];
    path = [
      pkgs.bash
      pkgs.bubblewrap
      pkgs.cacert
      pkgs.curl
      pkgs.gh
      pkgs.git
      pkgs.nodejs
      pkgs.openssh
      pkgs.python3
      pkgs.ripgrep
      pkgs.rsync
      pkgs.sqlite
    ];
    serviceConfig = {
      Type = "simple";
      User = "worker";
      Group = "worker";
      Environment = [
        "HOME=/var/lib/worker"
        "CHATTING_CONFIG_DIR=/etc/chatting"
      ];
      EnvironmentFile = "-/etc/chatting/worker.env";
      ExecStart = "${workerBin} --config ${workerConfigPath}";
      WorkingDirectory = "/var/lib/worker";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ workerConfigPath ];
      ReadWritePaths = [
        "/var/lib/worker"
        "/srv/chatting/workspace"
      ];
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
    };
  };
}
