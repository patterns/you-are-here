{
  description = "mini flake";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";

  };

  outputs = { self, nixpkgs }: {

    packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;

    defaultPackage.x86_64-linux = self.packages.x86_64-linux.hello;

  };
}
