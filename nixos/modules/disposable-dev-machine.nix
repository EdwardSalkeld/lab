{ pkgs, ... }:

{
  documentation.enable = false;

  programs.zsh.enable = true;

  users.users.edward = {
    shell = pkgs.zsh;
    extraGroups = [
      "docker"
      "networkmanager"
    ];
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  environment.systemPackages = with pkgs; [
    awscli2
    awslogs
    bat
    bun
    cmake
    curl
    dig
    direnv
    doctl
    fd
    fzf
    gcc
    gh
    git
    gnumake
    gnupg
    go
    graphviz
    hadolint
    htop
    jq
    kubectl
    lazygit
    luarocks
    mariadb.client
    neovim
    ninja
    nmap
    nodejs
    openssl
    opentofu
    pipx
    pkg-config
    postgresql
    pulumi
    python3
    restic
    ripgrep
    stow
    inetutils
    tflint
    tig
    tmux
    unzip
    uv
    vim
    wakeonlan
    wget
    xclip
    yq
    zsh
  ];
}
