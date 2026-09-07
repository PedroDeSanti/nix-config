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

  systemd.services.docker-homeassistant = {
    after = [ "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
  };
}
