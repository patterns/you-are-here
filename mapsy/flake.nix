{
  description = "minimal flake";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
    flake-utils.url = "github:numtide/flake-utils";

    # Used for shell.nix
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    overlays = [
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
    name = "mapsy"; # Project name that will be used in Zig
  in {
    # You can add NixOS modules if needed in the future
    nixosModules = {
      default = { ... }: {
        # Empty for now, but you can add imports here
      };
    };
  } // flake-utils.lib.eachSystem systems (
    system: let
      pkgs = import nixpkgs {
        inherit system overlays;
      };

      lib = pkgs.lib;

    in {
      # Make pkgs available
      legacyPackages = pkgs;

      # Create a package that can be built
      packages.default = pkgs.stdenv.mkDerivation {
        inherit name;
        src = ./.;
        nativeBuildInputs = [ pkgs.zigpkgs.master ];
        # Create a local Zig cache directory to avoid permission issues
        ZIG_GLOBAL_CACHE_DIR = "./zig-cache";

        buildPhase = ''
          # Use the local cache directory for Zig
          zig build --global-cache-dir ./zig-cache
        '';

      };

    });

  nixConfig = {
    extra-experimental-features = ["nix-command flakes" "ca-derivations"];
    allow-import-from-derivation = "true";
    extra-substituters = ["https://you-are-here.cachix.org"];
    extra-trusted-public-keys = ["you-are-here.cachix.org-1:NZT1KIQRJY6a/j1hLI4Eh80JrxCPDnLX3D0g+fW+4Lo="];
  };
}
