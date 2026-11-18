{
  config,
  pkgs,
  chattingRuntimePackage,
  codexPackage,
  ...
}:

let
  handlerConfigPath = "/etc/chatting/handler.json";
  workerConfigPath = "/etc/chatting/worker.json";
  bbmbBin = "${chattingRuntimePackage}/bin/bbmb-server";
  handlerBin = "${chattingRuntimePackage}/bin/chatting-handler";
  platformBin = "${chattingRuntimePackage}/bin/chatting-platform";
  workerBin = "${chattingRuntimePackage}/bin/chatting-worker";
in
{
  # Supervisors and executors outlive the manager unit. Keep their temporary
  # files outside systemd's per-start private /tmp, with no age-based cleanup.
  systemd.tmpfiles.rules = [
    "d /var/lib/worker/chatting-tmp 0700 worker worker -"
  ];

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
    unitConfig.RequiresMountsFor = [ "/srv/chatting/workspaces" ];
    restartTriggers = [
      config.environment.etc."chatting/worker.json".source
      config.environment.etc."chatting/codex-config.toml".source
    ];
    path = [
      pkgs.bash
      pkgs.bubblewrap
      pkgs.cacert
      # The worker runs `codex exec` as its agent (worker.json codex_command).
      # Codex is a static musl binary, so it needs no nix-ld here.
      codexPackage
      pkgs.curl
      pkgs.gh
      pkgs.git
      pkgs.nodejs
      pkgs.openssh
      pkgs.python314
      pkgs.ripgrep
      pkgs.rsync
      pkgs.sqlite
    ];
    # `gh auth setup-git` writes its own store path into ~/.gitconfig, which
    # breaks every GitHub fetch once a gh upgrade is garbage collected. Config
    # from the environment is read last: the empty value clears any helpers
    # from ~/.gitconfig, then this unit's gh is used instead.
    environment = {
      GIT_CONFIG_COUNT = "2";
      GIT_CONFIG_KEY_0 = "credential.https://github.com.helper";
      GIT_CONFIG_VALUE_0 = "";
      GIT_CONFIG_KEY_1 = "credential.https://github.com.helper";
      GIT_CONFIG_VALUE_1 = "!${pkgs.gh}/bin/gh auth git-credential";
    };
    serviceConfig = {
      Type = "simple";
      User = "worker";
      Group = "worker";
      Environment = [
        "HOME=/var/lib/worker"
        "TMPDIR=/var/lib/worker/chatting-tmp"
        "CHATTING_CONFIG_DIR=/etc/chatting"
        "CHATTING_MODEL_HIGH=gpt-6.1-terra"
        "CHATTING_MODEL_LOW=gpt-6-luna"
        # Personal mailbox classification runs as a thread of this worker,
        # sharing its TypeSafe key. It stays off until the cache path is set.
        # /var/lib/worker is already in ReadWritePaths.
        "CHATTING_PERSONAL_CACHE_PATH=/var/lib/worker/personal-inbox-cache.db"
        # Personal triage feedback is data in memory, refreshed per new mail.
        "CHATTING_PERSONAL_RULES_REPO=/srv/chatting/workspace/memory"
        # Skip routine bot updates using the reviewed owner policy in memory.
        # Keep useful results and forward on uncertainty or checker failure.
        # See chatting-notifications.md for decision and rollback checks.
        "CHATTING_NOTIFICATION_RULES_REPO=/srv/chatting/workspace/memory"
        # Summaries go through the logged-in Codex CLI, which is started with
        # --ignore-user-config and so does not see the model named in
        # codex-config.toml. Name it here or Codex picks its own default.
        "CHATTING_PERSONAL_SUMMARY_MODEL=gpt-6-luna"
      ];
      EnvironmentFile = config.sops.templates."chatting-worker.env".path;
      ExecStart = "${workerBin} --config ${workerConfigPath}";
      # Supervisors own running executors and reconnect to the next manager.
      # A worker restart must signal only the manager, not its whole cgroup.
      KillMode = "process";
      WorkingDirectory = "/var/lib/worker";
      NoNewPrivileges = true;
      # PrivateTmp is torn down on manager stop even with KillMode=process.
      # Surviving processes would lose finish sockets and writable temp space.
      PrivateTmp = false;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ workerConfigPath ];
      ReadWritePaths = [
        # ProtectSystem=strict otherwise makes shared /tmp read-only once
        # PrivateTmp is disabled. Some tools ignore the persistent TMPDIR.
        "/tmp"
        "/var/tmp"
        "/var/lib/worker"
        "/srv/chatting/workspace"
        "/srv/chatting/workspaces"
      ];
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
    };
  };

  # Read-mostly operator UI over the handler (9464) and worker (9465). Its
  # defaults are loopback 9466 and those two ports, so it needs no config file.
  # It keeps no state and holds no secrets.
  systemd.services.chatting-platform = {
    description = "Chatting platform UI";
    wantedBy = [ "chatting.target" ];
    partOf = [ "chatting.target" ];
    after = [
      "chatting-handler.service"
      "chatting-worker.service"
    ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = platformBin;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      IPAddressAllow = "localhost";
      IPAddressDeny = "any";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
    };
  };
}
