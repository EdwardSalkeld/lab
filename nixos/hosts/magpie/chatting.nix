{ pkgs, ... }:

let
  repoRoot = "/srv/chatting/repo";
  handlerConfigPath = "/etc/chatting/handler.json";
  workerConfigPath = "/etc/chatting/worker.json";
  runtimeHelperRoot = "${repoRoot}/deploy/host_runtime";
  runBbmb = "${runtimeHelperRoot}/run-bbmb.sh";
  runHandler = "${runtimeHelperRoot}/run-handler.sh";
  runWorker = "${runtimeHelperRoot}/run-worker.sh";
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
      Environment = [ "CHATTING_CONFIG_DIR=/etc/chatting" ];
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
      Environment = [
        "HOME=/var/lib/handler"
        "CHATTING_CONFIG_DIR=/etc/chatting"
      ];
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
      Environment = [
        "HOME=/var/lib/worker"
        "CHATTING_CONFIG_DIR=/etc/chatting"
      ];
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
