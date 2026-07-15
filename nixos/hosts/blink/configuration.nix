{ lib, pkgs, ... }:

let
  houseComposeDir = "/home/edward/develop/house/blink/docker";
  chattingComposeDir = "/home/edward/develop/chatting";
  dockerVolumeRoot = "/mnt/ssd4tb/docker-volumes";

  compose = "${pkgs.docker-compose}/bin/docker-compose";

  alloyConfig = pkgs.writeText "blink-alloy.alloy" ''
    local.file_match "local_files" {
      path_targets = [{"__path__" = "/host/*.log"}]
      sync_period = "5s"
    }

    loki.write "partridge_loki" {
      external_labels = {host = "blink"}
      endpoint {
        url = "https://loki.int.alcachofa.faith/loki/api/v1/push"
      }
    }

    loki.source.file "log_scrape" {
      targets = local.file_match.local_files.targets
      forward_to = [loki.write.partridge_loki.receiver]
      tail_from_end = true
    }

    loki.source.journal "read" {
      forward_to = [loki.write.partridge_loki.receiver]
      relabel_rules = loki.relabel.journal.rules
      max_age = "12h"
      path = "/host/journal"
      labels = {source = "journal"}
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label = "systemd_unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label = "systemd_hostname"
      }
      rule {
        source_labels = ["__journal__transport"]
        target_label = "systemd_transport"
      }
    }

    loki.relabel "docker" {
      forward_to = []
      rule {
        source_labels = ["__meta_docker_container_name"]
        target_label = "container_name"
      }
    }

    discovery.docker "linux" {
      host = "unix:///mnt/host/run/docker.sock"
    }

    loki.source.docker "default" {
      host = "unix:///mnt/host/run/docker.sock"
      targets = discovery.docker.linux.targets
      labels = {"source" = "docker"}
      relabel_rules = loki.relabel.docker.rules
      forward_to = [loki.write.partridge_loki.receiver]
    }
  '';

  houseComposeOverride = pkgs.writeText "blink-house-compose.override.yml" ''
    services:
      jellyfin:
        volumes:
          - ${dockerVolumeRoot}/docker_jfconfig:/config
          - ${dockerVolumeRoot}/docker_jfcache:/cache
      alloy:
        volumes:
          - ${alloyConfig}:/etc/alloy/config.alloy:ro
      pigallery2:
        volumes:
          - ${dockerVolumeRoot}/docker_pigallery2-storage:/app/data/db
  '';

  chattingComposeOverride = pkgs.writeText "blink-chatting-compose.override.yml" ''
    services:
      handler:
        volumes:
          - ${dockerVolumeRoot}/chatting_handler-data:/data
          - ${dockerVolumeRoot}/chatting_shared-temp:/tmp
          - ${dockerVolumeRoot}/chatting_gh-auth:/home/chatting/.config/gh
      worker:
        volumes:
          - ${dockerVolumeRoot}/chatting_worker-data:/data
          - ${dockerVolumeRoot}/chatting_html-output:/workspace/html
          - ${dockerVolumeRoot}/chatting_shared-temp:/tmp
          - ${dockerVolumeRoot}/chatting_codex-auth:/home/chatting/.codex
          - ${dockerVolumeRoot}/chatting_claude-auth:/home/chatting/.claude
          - ${dockerVolumeRoot}/chatting_gh-auth:/home/chatting/.config/gh
      site:
        volumes:
          - ${dockerVolumeRoot}/chatting_html-output:/site
  '';

  houseServices = [
    "jellyfin"
    "cadvisor"
    "node_exporter"
    "reverse-proxy"
    "alloy"
    "pigallery2"
    "database"
    "navidrome"
  ];

  chattingServices = [
    "bbmb"
    "handler"
    "worker"
    "site"
  ];

  composeService = { description, directory, services, files ? [ "docker-compose.yml" ], stopBefore ? [ ] }:
    let
      serviceArgs = lib.concatStringsSep " " services;
      fileArgs = lib.concatMapStringsSep " " (file: "-f ${file}") files;
      stopBeforeArgs = lib.concatStringsSep " " stopBefore;
      stopBeforeCommand = "${compose} ${fileArgs} stop ${stopBeforeArgs}";
      composeCommand = "${compose} ${fileArgs}";
    in
    {
      description = description;
      after = [
        "docker.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = directory;
        ExecStartPre = lib.optionals (stopBefore != [ ]) [
          "-${stopBeforeCommand}"
        ];
        ExecStart = "${composeCommand} up -d ${serviceArgs}";
        ExecStop = "${composeCommand} stop ${serviceArgs}";
        TimeoutStartSec = "10min";
        TimeoutStopSec = "5min";
      };
    };
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot/efi";
  };

  networking.hostName = "blink";
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [
      22
      80
      111
      443
      2049
      3101
      3306
      3456
      4533
      8080
      8083
      8096
      9100
      9464
      9465
      9466
      9876
      9877
    ];
    allowedUDPPorts = [
      111
      2049
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  services.fstrim.enable = true;
  services.smartd.enable = true;

  services.nfs.server = {
    enable = true;
    exports = ''
      /media/inbox 10.4.1.0/24(no_subtree_check,no_auth_nlm,insecure,anonuid=1000,anongid=1000,all_squash,rw)
      /mnt/ssd4tb/full/photos/inbox 10.4.1.0/24(no_subtree_check,no_auth_nlm,insecure,anonuid=1000,anongid=1000,all_squash,rw)
      /mnt/ssd4tb/full/apple 10.4.1.0/24(no_subtree_check,no_auth_nlm,insecure,anonuid=1000,anongid=1000,all_squash,rw)
    '';
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/redhdd 0755 root root -"
    "d /mnt/ext2tb 0755 root root -"
    "d /mnt/ext2tb/1 0755 root root -"
    "d /mnt/ext2tb/3 0755 root root -"
    "d /mnt/ext2tb/4 0755 root root -"
    "d /mnt/ssd4tb 0755 root root -"
    "d /mnt/ssd4tb/docker-volumes 0755 root root -"
    "d /media 0755 root root -"
    "L /media/inbox - - - - /mnt/ssd4tb/partial/record-library/inbox"
  ];

  systemd.services = {
    blink-house-compose = composeService {
      description = "Blink house Docker Compose services";
      directory = houseComposeDir;
      files = [
        "docker-compose.yml"
        houseComposeOverride
      ];
      services = houseServices;
      stopBefore = [
        "grafana"
        "prometheus"
        "loki"
        "promtail"
        "jogon"
        "bitwarden-backup"
      ];
    };

    blink-chatting-compose = composeService {
      description = "Blink Chatting Docker Compose services";
      directory = chattingComposeDir;
      files = [
        "docker-compose.yml"
        chattingComposeOverride
      ];
      services = chattingServices;
    };
  };

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [
      "docker"
      "networkmanager"
      "systemd-journal"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    bind.dnsutils
    cmake
    curl
    docker-compose
    fd
    fzf
    gcc
    git
    go
    gnumake
    htop
    lsof
    mariadb
    netcat-openbsd
    ninja
    nmap
    nodejs
    pciutils
    pkg-config
    restic
    ripgrep
    rsync
    screen
    sqlite
    tcpdump
    tmux
    traceroute
    usbutils
    vim
    wget
  ];

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "25.11";
}
