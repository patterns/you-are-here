{
  description = "hello flake";

  inputs = {
    ####nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  };

  outputs = { self, nixpkgs, ... }:
  let
    # System types to support.
    supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
    # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    # Nixpkgs instantiated for supported system types.
    nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

  in
  {
    # Provide some binary packages for selected system types.
    packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
        # The default package for 'nix build'. This makes sense if the
        # flake provides only one package or there is a clear "main"
        # package.
          default = pkgs.hello;

        });


        # Add dependencies that are only needed for development
        devShells = forAllSystems (system:
          let
            pkgs = nixpkgsFor.${system};
          in
          {
            default = pkgs.mkShell {
                buildInputs = with pkgs; [ zig zls lldb s2geometry cairo ];
          };
        });

  };
}

