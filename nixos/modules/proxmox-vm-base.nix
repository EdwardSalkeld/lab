{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  networking.useDHCP = lib.mkDefault true;

  services.openssh.enable = true;
  services.qemuGuest.enable = true;
  services.fstrim.enable = true;

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = true;
  };

  nix.gc = {
    automatic = true;
    dates = lib.mkDefault "weekly";
    options = "--delete-older-than 14d";
  };

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Keep edward's systemd user manager persistently active. Otherwise a
    # short-lived SSH session churning open/closed during a `nixos-rebuild
    # switch` races the switch's "reload user units" step (logind loses the
    # uid-1000 user object mid-reload), failing the whole switch. Lingering
    # makes the deploy robust regardless of who is logged in.
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };

  users.users.billy = {
    isNormalUser = true;
    # Keep billy's systemd user manager persistently active for the same reason
    # as edward: a short-lived SSH session must not be able to race a deploy's
    # "reload user units" step.
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    lazygit
    nettools
    ripgrep
    vim
    wget
  ];

  system.stateVersion = "25.11";
}
