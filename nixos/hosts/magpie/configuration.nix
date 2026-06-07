{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "magpie";
  networking.networkmanager.enable = true;
  virtualisation.diskSize = 12 * 1024;

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    tree
  ];
}
