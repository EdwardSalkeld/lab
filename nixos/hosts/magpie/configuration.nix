{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./chatting.nix
    ./chatting-config.nix
    ./chatting-secrets.nix
    ./chatting-prune.nix
    ./forgejo-runner.nix
  ];

  networking.hostName = "magpie";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Magpie's small root disk fills quickly with Nix build/store churn from the
  # worker. Remove every unreachable store path at the daily run rather than
  # retaining it for 14 days; only live generations and paths remain.
  nix.gc = {
    dates = "daily";
    options = "-d";
  };

  # The worker can create several GiB of dead build outputs between daily GC
  # runs. Check frequently, but only collect when root has crossed the
  # high-water mark, preserving useful build cache while retaining about 6 GiB
  # of headroom on the 24 GiB root filesystem.
  systemd.services.nix-gc-on-root-pressure = {
    description = "Collect unreachable Nix paths when Magpie root is under pressure";
    path = with pkgs; [ coreutils gawk nix ];
    serviceConfig.Type = "oneshot";
    script = ''
      root_usage="$(df -P / | awk 'NR == 2 { sub(/%$/, "", $5); print $5 }')"

      if [ "$root_usage" -lt 75 ]; then
        echo "root usage is ''${root_usage}%; below the 75% Nix GC threshold"
        exit 0
      fi

      echo "root usage is ''${root_usage}%; collecting unreachable Nix paths"
      nix-collect-garbage -d
    '';
  };

  systemd.timers.nix-gc-on-root-pressure = {
    description = "Check Magpie root usage for Nix GC pressure collection";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
      RandomizedDelaySec = "2m";
      Unit = "nix-gc-on-root-pressure.service";
    };
  };

  # LAN access to the chatting services: bbmb broker metrics (9877), message
  # handler metrics (9464), and the worker activity UI (9465). No auth on these,
  # so they rely on being LAN-only. Node exporter (9100) is opened separately by
  # the shared VM base module.
  networking.firewall.allowedTCPPorts = [
    9464
    9465
    9877
  ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # Let repo-pinned generic Linux tool binaries run on NixOS. This keeps
  # commands like `npm run lint` working when a project depends on a prebuilt
  # glibc-linked CLI such as Biome.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];
  };

  # A deploy must leave the chatting split runtime running; if any of these are
  # down after a switch, the remote-deploy wrapper rolls back and, failing that,
  # starts them, so a bad or half-applied switch can't silently down chatting.
  alcachofa.remoteDeploy.postSwitchHealthchecks = [
    "chatting-bbmb.service"
    "chatting-handler.service"
    "chatting-worker.service"
  ];

  users.users.edward = {
    extraGroups = [
      "networkmanager"
      "systemd-journal"
      "wheel"
    ];
    packages = with pkgs; [
      tree
    ];
  };

  users.users.billy.extraGroups = [
    "systemd-journal"
  ];

  users.users.bbmb = {
    isSystemUser = true;
    group = "bbmb";
  };

  users.users.handler = {
    isSystemUser = true;
    group = "handler";
  };

  users.users.worker = {
    isSystemUser = true;
    group = "worker";
  };

  users.groups.bbmb = { };
  users.groups.handler = { };
  users.groups.worker = { };

  systemd.tmpfiles.rules = [
    "d /srv/chatting 0755 root root -"
    "d /srv/chatting/repo 0755 root root -"
    "d /srv/chatting/workspace 0750 worker worker -"
    # Shared drop point for Telegram attachments: the handler downloads into
    # it, the worker (a different OS user) reads them back. 0755 so the worker
    # can traverse; handler owns it so it can write. Pre-created here rather
    # than left to the handler's runtime MkdirAll, whose 0700 (UMask=0077)
    # would lock the worker out.
    "d /srv/chatting/attachments 0755 handler handler -"
    "d /etc/chatting 0755 root root -"
    "d /var/lib/bbmb 0750 bbmb bbmb -"
    "d /var/lib/handler 0700 handler handler -"
    "d /var/lib/worker 0700 worker worker -"
    "d /var/lib/worker/.codex 0700 worker worker -"
    # Keep worker auth/session state in /var/lib/worker/.codex, but source the
    # model/defaults file from the declarative /etc/chatting render.
    "L+ /var/lib/worker/.codex/config.toml - - - - /etc/chatting/codex-config.toml"
  ];

  environment.systemPackages = with pkgs; [
    bubblewrap
    cacert
    curl
    gcc
    git
    gh
    go
    gnumake
    htop
    nodejs
    python3
    ripgrep
    rsync
    sqlite
    tmux
    tree
    vim
  ];
}
