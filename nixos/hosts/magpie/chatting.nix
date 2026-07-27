{ pkgs, ... }:

let
  repoRoot = "/srv/chatting/repo";
  handlerConfigPath = "/etc/chatting/handler.json";
  workerConfigPath = "/etc/chatting/worker.json";
  runBbmb = "${repoRoot}/deploy/magpie/run-bbmb.sh";
  runHandler = "${repoRoot}/deploy/magpie/run-handler.sh";
  runWorker = "${repoRoot}/deploy/magpie/run-worker.sh";
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
    unitConfig.ConditionPathExists = runBbmb;
    path = [ pkgs.bash ];
    serviceConfig = {
      Type = "simple";
      User = "bbmb";
      Group = "bbmb";
      ExecStart = runBbmb;
      WorkingDirectory = repoRoot;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ repoRoot ];
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
    unitConfig.ConditionPathExists = [
      runHandler
      handlerConfigPath
    ];
    path = [ pkgs.bash ];
    serviceConfig = {
      Type = "simple";
      User = "handler";
      Group = "handler";
      Environment = [ "HOME=/var/lib/handler" ];
      EnvironmentFile = "-/etc/chatting/handler.env";
      ExecStart = runHandler;
      WorkingDirectory = repoRoot;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [
        repoRoot
        handlerConfigPath
      ];
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
      runWorker
      workerConfigPath
      "/srv/chatting/workspace"
    ];
    path = [ pkgs.bash ];
    serviceConfig = {
      Type = "simple";
      User = "worker";
      Group = "worker";
      Environment = [ "HOME=/var/lib/worker" ];
      EnvironmentFile = "-/etc/chatting/worker.env";
      ExecStart = runWorker;
      WorkingDirectory = repoRoot;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [
        repoRoot
        workerConfigPath
      ];
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
