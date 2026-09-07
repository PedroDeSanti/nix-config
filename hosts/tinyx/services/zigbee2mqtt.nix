# Zigbee2MQTT with the SONOFF ZBDongle-E (EFR32MG21, `ember` adapter).
#
# The module rewrites configuration.yaml from `settings` on every start; devices and
# groups live in devices.yaml / groups.yaml, which Zigbee2MQTT owns and keeps. Secrets
# (network key, PAN IDs, MQTT password) are `!secret` references to
# /srv/zigbee2mqtt/secret.yaml, outside the repo and the Nix store.
#
# The dongle gets a stable /dev/zigbee name from a udev rule keyed on its USB serial.
# The service is bound to that device: it stops when the dongle is pulled and starts
# again when it is plugged back in.
{ ... }:
let
  dongleSerial = "e22657476ed4f011958bc42dc6dc3c96";
in
{
  services.zigbee2mqtt = {
    enable = true;
    dataDir = "/srv/zigbee2mqtt";
    settings = {
      version = 5;
      homeassistant.enabled = true;
      permit_join = false;
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://127.0.0.1:1883";
        user = "zigbee2mqtt";
        password = "!secret mqtt_password";
      };
      serial = {
        port = "/dev/zigbee";
        adapter = "ember";
        baudrate = 115200;
      };
      frontend = {
        enabled = true;
        host = "127.0.0.1";   # only via Caddy: z2m.lab.desanti.dev
        port = 8099;          # 8080 is Caddy's tunnel listener
      };
      advanced = {
        log_level = "info";
        network_key = "!secret network_key";
        # PAN IDs are broadcast in clear text in every Zigbee beacon: not secrets.
        pan_id = 44885;
        ext_pan_id = [ 210 222 130 158 41 239 142 23 ];
      };
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ENV{ID_USB_SERIAL_SHORT}=="${dongleSerial}", SYMLINK+="zigbee", TAG+="systemd", ENV{SYSTEMD_WANTS}+="zigbee2mqtt.service"
  '';

  systemd.services.zigbee2mqtt = {
    bindsTo = [ "dev-zigbee.device" ];
    after = [ "dev-zigbee.device" "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
  };

  # Migrated state arrives root-owned; fix ownership at activation, before the service starts.
  systemd.tmpfiles.rules = [ "Z /srv/zigbee2mqtt 0750 zigbee2mqtt zigbee2mqtt -" ];
}
