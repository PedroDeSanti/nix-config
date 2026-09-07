{
  description = "NixOS hosts: tinyx (homelab), more to come";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # `latest` tracks disko's stable releases.
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # release branch must match the nixpkgs branch above.
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, home-manager, ... }: {
    # `nix run .#disko` from the installer ISO: same disko and nixpkgs as the lock,
    # so the tool that partitions is the one that generates fileSystems.
    packages.x86_64-linux.disko = disko.packages.x86_64-linux.disko;

    nixosConfigurations.tinyx = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./hosts/tinyx/disko.nix
        ./hosts/tinyx/hardware-configuration.nix
        ./hosts/tinyx
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.santi = import ./home/santi/tinyx.nix;
        }
      ];
    };
  };
}
