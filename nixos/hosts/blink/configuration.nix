{
  config,
  lib,
  pkgs,
  ...
}:

let
  houseComposeDir = "/home/edward/develop/house/blink/docker";
  wantlistComposeDir = "/home/edward/develop/untitled-music-project/deploy/prod";
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

  wantlistServices = [
    "api"
    "worker"
  ];

  composeService =
    {
      description,
      directory,
      services,
      files ? [ "docker-compose.yml" ],
      stopBefore ? [ ],
      after ? [ ],
      requires ? [ ],
    }:
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
      ]
      ++ after;
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ] ++ requires;
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
  networking.modemmanager.enable = false;
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.secrets."networkmanager/lagarza".path ];
    profiles.LaGarza = {
      connection = {
        id = "LaGarza";
        type = "wifi";
        interface-name = "wlo1";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "LaGarza";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$LAGARZA_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  # This is the existing Blink host key, not a newly generated one. Restore
  # /etc/ssh from the pre-reinstall backup before the first reboot: sops-nix
  # uses it to decrypt the Wi-Fi PSK and NetworkManager then reconnects.
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets."networkmanager/lagarza" = {
      sopsFile = ./secrets/networkmanager.yaml;
      format = "yaml";
    };
  };

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
    NetworkManager-ensure-profiles = {
      after = [ "sops-nix.service" ];
      requires = [ "sops-nix.service" ];
    };

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

    blink-wantlist-compose = composeService {
      description = "Blink Wantlist Docker Compose services";
      directory = wantlistComposeDir;
      services = wantlistServices;
      after = [ "blink-house-compose.service" ];
      requires = [ "blink-house-compose.service" ];
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

  # Dedicated, declarative maintenance account.  Keep this separate from
  # Edward's account so an automated SSH key is not coupled to his login.
  users.users.billy = {
    isNormalUser = true;
    extraGroups = [
      "docker"
      "networkmanager"
      "systemd-journal"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
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
