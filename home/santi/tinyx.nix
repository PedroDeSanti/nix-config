# santi on tinyx (headless): core + the T3 Code server.
{ ... }: {
  imports = [
    ./common/core
    ./common/optional/t3code.nix
  ];
  home.stateVersion = "26.05";
}
