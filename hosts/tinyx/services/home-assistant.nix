# Home Assistant as a container. The NixOS module only pays off when automations and
# dashboards are generated from Nix; here they are edited in the UI, so the container
# keeps upgrades independent of nixpkgs and the config directory a plain bind mount.
#
# /srv/homeassistant is the config dir migrated from the notebook. Hand-written YAML
# there is tracked in its own git repo; .storage/ and the database are state
# (btrbk + restic). Reached through Caddy only: ha.lab.desanti.dev (private) and later
# ha.desanti.dev (tunnel) -> configuration.yaml has http.trusted_proxies for 127.0.0.1.
{ ... }:
{
  virtualisation.oci-containers.containers.homeassistant = {
    image = "ghcr.io/home-assistant/home-assistant:2026.6.3";
    volumes = [
      "/srv/homeassistant:/config"
      "/etc/localtime:/etc/localtime:ro"
      "/run/dbus:/run/dbus:ro"   # bluetooth integration; without it the log fills with bluez errors
    ];
    environment.TZ = "America/Sao_Paulo";
    extraOptions = [
      "--network=host"   # mDNS/SSDP discovery, and the broker on 127.0.0.1
      "--memory=1g"
    ];
  };

  # Plain HTTP on the LAN: the HA "internal URL" that phones on the home Wi-Fi and LAN
  # devices fetching media use. Works with no internet and no tailnet.
  networking.firewall.interfaces.wlp2s0.allowedTCPPorts = [ 8123 ];

  systemd.services.docker-homeassistant = {
    after = [ "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
  };

  tinyx.services.homeassistant = {
    name = "Home Assistant";
    subdomain = "ha";
    port = 8123;
    public = true;
    group = "Casa";
    order = 10;
    icon = "home-assistant.png";
    description = "Automacao da casa";
    widget = { type = "homeassistant"; url = "http://127.0.0.1:8123"; key = "{{HOMEPAGE_VAR_HA_TOKEN}}"; };
  };
}
