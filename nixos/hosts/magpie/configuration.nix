{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./chatting.nix
    ./chatting-prune.nix
  ];

  networking.hostName = "magpie";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  # Let Partridge's Prometheus scrape the chatting metrics: bbmb broker (9877)
  # and the message handler (9464). Node exporter (9100) is opened separately by
  # the shared VM base module.
  networking.firewall.allowedTCPPorts = [
    9464
    9877
  ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

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

  users.users.billy = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "systemd-journal"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
    ];
  };

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
    "d /etc/chatting 0755 root root -"
    "d /var/lib/bbmb 0750 bbmb bbmb -"
    "d /var/lib/handler 0700 handler handler -"
    "d /var/lib/worker 0700 worker worker -"
  ];

  environment.systemPackages = with pkgs; [
    bubblewrap
    cacert
    curl
    gcc
    git
    gh
    go
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
