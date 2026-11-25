{ lib }:

let
  common = import ../common.nix;
  builders = import ../builders.nix { inherit lib common; };
  groupArgs = { inherit lib common builders; };
in
{
  apiVersion = 1;
  deleteRules = [
    {
      orgId = 1;
      uid = "cf5pa2mc5o0zkc";
    }
    {
      orgId = 1;
      uid = "af5pb11hibn5sd";
    }
    {
      orgId = 1;
      uid = "aenyejmx1k2rka";
    }
    {
      orgId = 1;
      uid = "df14h5t71ue4gc";
    }
    {
      orgId = 1;
      uid = "fourth-backblaze-completion";
    }
    {
      orgId = 1;
      uid = "fourth-backblaze-duration";
    }
  ];
  groups = lib.concatMap (file: import file groupArgs) [
    ./octopus.nix
    ./availability.nix
    ./systemd.nix
    ./disk-space.nix
    ./mcm.nix
    ./backups.nix
  ];
}
