# Mosquitto: MQTT broker between Zigbee2MQTT and Home Assistant. Native module rather
# than a container: users, passwords and per-topic ACLs are declared here, and the
# daemon is 2 MB of C. Not reachable from the LAN (firewall); loopback and tailnet only.
# Passwords (plain, hashed by the module at start) live in /etc/secrets/mosquitto/.
{ ... }:
{
  services.mosquitto = {
    enable = true;
    dataDir = "/srv/mosquitto";
    listeners = [
      {
        port = 1883;
        settings.allow_anonymous = false;
        users = {
          homeassistant = {
            passwordFile = "/etc/secrets/mosquitto/homeassistant.pass";
            acl = [ "readwrite #" ];
          };
          zigbee2mqtt = {
            passwordFile = "/etc/secrets/mosquitto/zigbee2mqtt.pass";
            acl = [
              "readwrite zigbee2mqtt/#"
              "readwrite homeassistant/#"   # MQTT discovery announcements
            ];
          };
        };
      }
    ];
  };

  systemd.tmpfiles.rules = [ "d /srv/mosquitto 0700 mosquitto mosquitto -" ];

  tinyx.services.mosquitto = {
    name = "Mosquitto";
    group = "Infra";
    order = 20;
    icon = "mosquitto.png";
    description = "Broker MQTT, porta 1883";
    monitor = "tcp://127.0.0.1:1883";
  };
}
