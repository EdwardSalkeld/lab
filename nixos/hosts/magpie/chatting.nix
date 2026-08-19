{ config, pkgs, chattingRuntimePackage, codexPackage, goosePackage, ... }:

let
  handlerConfigPath = "/etc/chatting/handler.json";
  workerConfigPath = "/etc/chatting/worker.json";
  bbmbBin = "${chattingRuntimePackage}/bin/bbmb-server";
  handlerBin = "${chattingRuntimePackage}/bin/chatting-handler";
  workerBin = "${chattingRuntimePackage}/bin/chatting-worker";
  # Which OpenRouter model goose runs. Change here, not in chatting.
  gooseModel = "anthropic/claude-sonnet-4.6";
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
    # Restart the handler when its rendered config changes, so declarative
    # config edits (e.g. allowed egress channels) actually take effect on a
    # deploy instead of waiting for the next unrelated restart.
    restartTriggers = [ config.environment.etc."chatting/handler.json".source ];
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
      EnvironmentFile = config.sops.templates."chatting-handler.env".path;
      ExecStart = "${handlerBin} --config ${handlerConfigPath}";
      WorkingDirectory = "/var/lib/handler";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ handlerConfigPath ];
      ReadWritePaths = [
        "/var/lib/handler"
        # Handler downloads Telegram attachments here for the worker to read;
        # /srv is read-only under ProtectSystem=strict without this.
        "/srv/chatting/attachments"
      ];
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
    restartTriggers = [
      config.environment.etc."chatting/worker.json".source
      config.environment.etc."chatting/codex-config.toml".source
    ];
    path = [
      pkgs.bash
      pkgs.bubblewrap
      pkgs.cacert
      # The worker runs `codex exec` as its agent (worker.json codex_command).
      # Codex is a static musl binary, so it needs no nix-ld here. Sourced from
      # nixpkgs-unstable because 25.11 pins a release too old for gpt-5.4.
      codexPackage
      # goose is the alternative harness, selected by worker.json `executor`.
      # Present on the path regardless so switching executor is a config change
      # rather than a rebuild of the unit.
      goosePackage
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
        # goose reads its whole configuration from the environment, so which
        # model it runs is goose's business rather than chatting's — the same
        # split as Codex, which takes its model from codex-config.toml. Inert
        # while worker.json selects the Codex executor.
        "GOOSE_PROVIDER=openrouter"
        "GOOSE_MODEL=${gooseModel}"
        # auto is what makes an unattended run possible: without it goose stops
        # to ask before each tool call and the worker just times out.
        "GOOSE_MODE=auto"
        # Summarise rather than fail when a long task overflows the window.
        "GOOSE_CONTEXT_STRATEGY=summarize"
        # Session naming spends an extra model call per run for a label nothing
        # reads, since the worker passes --no-session.
        "GOOSE_DISABLE_SESSION_NAMING=true"
      ];
      EnvironmentFile = config.sops.templates."chatting-worker.env".path;
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
