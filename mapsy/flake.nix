{
  description = "hello flake";

  inputs = {
    ####nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
      ####systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
  in
  {
    ##packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;
    ##defaultPackage.x86_64-linux = self.packages.x86_64-linux.hello;
      packages = systems (pkgs: {
        default = pkgs.hello;
      });

      devShells = systems (pkgs: {
        default = pkgs.mkShell (
          with pkgs;
          {
            buildInputs = [
              zig
              ####zls
              # You can add `just` to invoke `zig run`, `zig build-exe`, etc
              # with specific arguments.
              ####cairo
            ];
          }
        );
      });

  };
}
