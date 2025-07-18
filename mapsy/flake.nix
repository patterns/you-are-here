{
  description = "hello flake";

  inputs = {
    ####nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

  in
  {
    ####packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;
    ####defaultPackage.x86_64-linux = self.packages.x86_64-linux.hello;
        packages.default = pkgs.hello;
#        packages.default = pkgs.stdenv.mkDerivation {
#          name = "mapsy";
#          src = ./.;
#          buildInputs = [
#            pkgs.zig
#          ];
#        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            ####pkgs.git
            ####pkgs.gcc
            ####pkgs.python3
            pkgs.zig
            ####pkgs.cairo
          ];
        };


  });
}

