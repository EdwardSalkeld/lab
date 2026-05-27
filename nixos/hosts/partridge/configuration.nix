{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "partridge";
  networking.networkmanager.enable = true;

  users.users.edward.packages = with pkgs; [
    tree
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
