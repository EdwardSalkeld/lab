{ ... }:

{
  networking.hostName = "nixos-01";

  # Copy the generated hardware configuration from the installed VM here before
  # making this host fully repo-managed.
  # imports = [ ./hardware-configuration.nix ];
}
