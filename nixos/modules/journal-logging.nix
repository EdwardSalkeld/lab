{ lib, ... }:

{
  imports = [ ./journal-to-loki.nix ];

  # Keep the complete journal in Loki and bound the copy on each VM's root disk.
  alcachofa.journalToLoki.enable = lib.mkDefault true;
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=64M
  '';
}
