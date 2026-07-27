{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "chatting";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  users.users.edward.packages = with pkgs; [
    tree
  ];

  users.users.billy = {
    isNormalUser = true;
    extraGroups = [
      "systemd-journal"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
    ];
  };

  users.groups.handler = { };
  users.groups.worker = { };
  users.groups.bbmb = { };

  users.users.handler = {
    isSystemUser = true;
    group = "handler";
    home = "/var/lib/handler";
    createHome = false;
  };

  users.users.worker = {
    isSystemUser = true;
    group = "worker";
    home = "/var/lib/worker";
    createHome = false;
  };

  users.users.bbmb = {
    isSystemUser = true;
    group = "bbmb";
    home = "/var/lib/bbmb";
    createHome = false;
  };

  systemd.tmpfiles.rules = [
    "d /etc/chatting 0750 root root -"
    "d /srv/chatting 0755 root root -"
    "d /srv/chatting/repo 0755 root root -"
    "d /srv/chatting/workspace 0750 worker worker -"
    "d /var/lib/handler 0700 handler handler -"
    "d /var/lib/handler/telegram-attachments 0700 handler handler -"
    "d /var/lib/worker 0700 worker worker -"
    "d /var/lib/bbmb 0750 bbmb bbmb -"
  ];

  environment.systemPackages = with pkgs; [
    bubblewrap
    curl
    gh
    git
    go
    htop
    python313
    ripgrep
    rsync
    sqlite
    tmux
    tree
    uv
    vim
    wget
    nodejs
  ];
}
