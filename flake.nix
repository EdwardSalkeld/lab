{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    octopus-dl = {
      url = "github:EdwardSalkeld/octopus-dl";
      flake = false;
    };
    linear-export = {
      url = "github:EdwardSalkeld/linear-export";
      flake = false;
    };
    exercise-tracker = {
      url = "github:EdwardSalkeld/exercise-tracker";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sops-nix, octopus-dl, linear-export, exercise-tracker, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      bitwardenMirror = pkgs.buildGoModule {
        pname = "bitwarden-mirror";
        version = "0.1.0";
        src = ./tools/bitwarden-mirror;
        vendorHash = null;
        subPackages = [ "cmd/bitwarden-mirror" ];
      };
      octopusDl = pkgs.buildGoModule {
        pname = "octopus-dl";
        version = "0.1.0";
        src = octopus-dl;
        vendorHash = null;
        subPackages = [ "." ];
        # Tests run in CI; skip them here so the build does not compile the
        # CGO sqlite test driver (a ~250k-line C file, slow and disk-hungry)
        # that the binary itself never uses.
        doCheck = false;
      };
      linearExport = pkgs.buildGoModule {
        pname = "linear-export";
        version = "0.1.0";
        src = linear-export;
        vendorHash = null;
        subPackages = [ "." ];
        # Tests run in CI; skip them here so the build does not compile the
        # CGO sqlite test driver (a ~250k-line C file, slow and disk-hungry)
        # that the binary itself never uses.
        doCheck = false;
      };
      exerciseTracker = pkgs.buildGoModule {
        pname = "exercise-tracker";
        version = "0.1.0";
        src = exercise-tracker;
        vendorHash = null;
        subPackages = [ "cmd/exercise-tracker" ];
        # Tests run in CI; the nix build only needs the binary.
        doCheck = false;
        # The db-setup unit applies these migrations at activation, so they must
        # ship in the package output, not just the source tree.
        postInstall = ''
          install -Dm644 sql/migrations/*.sql -t $out/share/exercise-tracker/sql/migrations/
        '';
      };
    in
    {
      packages.${system} = {
        bitwarden-mirror = bitwardenMirror;
        octopus-dl = octopusDl;
        linear-export = linearExport;
        exercise-tracker = exerciseTracker;
        default = bitwardenMirror;
      };

      checks.${system} = {
        bitwarden-mirror-go-tests = pkgs.runCommand "bitwarden-mirror-go-tests"
          {
            nativeBuildInputs = [ pkgs.go ];
            src = ./tools/bitwarden-mirror;
          }
          ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR"
            export GOCACHE="$TMPDIR/go-cache"
            go test ./...
            touch "$out"
          '';

        partridge = self.nixosConfigurations.partridge.config.system.build.toplevel;
        blink = self.nixosConfigurations.blink.config.system.build.toplevel;
      };

      nixosConfigurations = {
        blink = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/hosts/blink/configuration.nix
          ];
        };

        partridge = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            bitwardenMirrorPackage = bitwardenMirror;
            octopusDlPackage = octopusDl;
            linearExportPackage = linearExport;
            exerciseTrackerPackage = exerciseTracker;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/remote-deploy.nix
            ./nixos/hosts/partridge/configuration.nix
          ];
        };

        magpie = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/disposable-dev-machine.nix
            ./nixos/modules/remote-deploy.nix
            ./nixos/hosts/magpie/configuration.nix
          ];
        };
      };
    };
}
