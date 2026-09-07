{
  description = "nix-config — NixOS hosts (tinyx homelab, ...)";

  inputs = {
    # Canal stable pinado. Atualizar com `nix flake update` e revisar o diff do lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Particionamento declarativo. `latest` = última release estável do disko.
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Config de usuário (git, shell, ...). release-26.05 casa com o nixpkgs acima;
    # follows = um só nixpkgs no closure.
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, home-manager, ... }: {
    # `nix run .#disko` na ISO: usa o MESMO disko e o MESMO nixpkgs do lock
    # (evita baixar um 2º nixpkgs para a RAM da ISO e garante que quem particiona == quem gera fileSystems)
    packages.x86_64-linux.disko = disko.packages.x86_64-linux.disko;

    nixosConfigurations.tinyx = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./hosts/tinyx/disko.nix                   # discos, partições, subvolumes → gera fileSystems/swapDevices
        ./hosts/tinyx/hardware-configuration.nix  # gerado por nixos-generate-config --no-filesystems
        ./hosts/tinyx                             # default.nix: tudo o mais
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;      # mesmo pkgs/overlays do sistema
          home-manager.useUserPackages = true;    # instala em /etc/profiles/per-user, não em ~/.nix-profile
          home-manager.users.santi = import ./home/santi/tinyx.nix;
        }
      ];
    };
  };
}
