{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {
      partridge = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./nixos/modules/proxmox-vm-base.nix
          ./nixos/hosts/partridge/configuration.nix
        ];
      };
    };
  };
}
