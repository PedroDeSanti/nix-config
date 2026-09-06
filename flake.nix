{
  description = "nix-config — NixOS hosts (tinyx homelab, ...)";

  inputs = {
    # Canal stable pinado. Atualizar com `nix flake update` e revisar o diff do lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Particionamento declarativo. `latest` = última release estável do disko.
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }: {
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
      ];
    };
  };
}
