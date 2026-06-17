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
  };

  outputs = { self, nixpkgs, sops-nix, octopus-dl, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      workoutServiceSrc = pkgs.runCommand "workout-service-src" { } ''
        cp -R ${builtins.fetchGit {
          url = "https://github.com/EdwardSalkeld/exercise-tracker.git";
          ref = "refs/heads/main";
          rev = "f31b9f4e63176a73daa70dd3c75a9e1ef072cf60";
        }} "$out"
        chmod -R u+w "$out"
        substituteInPlace "$out/go.mod" --replace-fail 'go 1.26.0' 'go 1.25.0'
        rm -rf "$out/vendor"
      '';
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
      };
      workoutService = pkgs.buildGoModule {
        pname = "workout-service";
        version = "0.1.0";
        src = workoutServiceSrc;
        vendorHash = null;
        subPackages = [ "cmd/workout-service" ];
        preBuild = ''
          rm -rf vendor
        '';
        postInstall = ''
          mkdir -p $out/share/workout-service
          cp -R sql $out/share/workout-service/
        '';
      };
    in
    {
      packages.${system} = {
        bitwarden-mirror = bitwardenMirror;
        octopus-dl = octopusDl;
        workout-service = workoutService;
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
      };

      nixosConfigurations = {
        partridge = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            bitwardenMirrorPackage = bitwardenMirror;
            octopusDlPackage = octopusDl;
            workoutServicePackage = workoutService;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/hosts/partridge/configuration.nix
          ];
        };

        magpie = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/disposable-dev-machine.nix
            ./nixos/hosts/magpie/configuration.nix
          ];
        };
      };
    };
}
