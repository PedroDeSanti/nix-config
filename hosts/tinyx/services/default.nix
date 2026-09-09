{ ... }: {
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./btrbk.nix
    ./restic.nix
    ./mosquitto.nix
    ./zigbee2mqtt.nix
    ./home-assistant.nix
    ./matter-hub.nix
    ./adguardhome.nix
    ./homepage.nix
    ./registry.nix
    ./securo.nix
  ];
}
