# Home Assistant Matter Hub: exposes HA entities as a Matter bridge so Alexa (Echo Dot 5)
# and other Matter controllers drive them locally, without a vendor skill or cloud.
# Community fork (RiDDiX) of the archived t0bst4r project.
#
# Matter is mDNS + UDP on the LAN, so: host network, mDNS pinned to the Wi-Fi interface
# (otherwise the tailnet addresses get advertised and controllers try to reach them),
# and the global IPv6 stripped from the advertisement (the ISP prefix rotates; the Echo
# reaches us over link-local anyway). Alexa only commissions on port 5540.
#
# Token: /etc/secrets/matter-hub.env holds HAMH_HOME_ASSISTANT_ACCESS_TOKEN, a long-lived
# HA token. Web UI on 8482, reached only through Caddy (matter.lab.desanti.dev).
{ ... }:
{
  virtualisation.oci-containers.containers.matter-hub = {
    image = "ghcr.io/riddix/home-assistant-matter-hub:2.0.56";
    volumes = [ "/srv/matter-hub:/data" ];
    environmentFiles = [ "/etc/secrets/matter-hub.env" ];
    environment = {
      HAMH_HOME_ASSISTANT_URL = "http://127.0.0.1:8123/";
      HAMH_LOG_LEVEL = "info";
      HAMH_HTTP_PORT = "8482";
      HAMH_MDNS_NETWORK_INTERFACE = "wlp2s0";
      HAMH_MDNS_STRIP_GLOBAL_IPV6 = "true";
    };
    extraOptions = [ "--network=host" ];
  };

  systemd.services.docker-matter-hub = {
    after = [ "docker-homeassistant.service" ];
    wants = [ "docker-homeassistant.service" ];
  };

  # Matter commissioning/operational traffic and mDNS, LAN side only.
  networking.firewall.interfaces.wlp2s0 = {
    allowedUDPPorts = [ 5353 5540 5541 ];
    allowedTCPPorts = [ 5540 5541 ];
  };

  tinyx.services.matter-hub = {
    name = "Matter Hub";
    subdomain = "matter";
    port = 8482;
    group = "Casa";
    order = 30;
    icon = "matter.png";
    description = "Ponte Matter para a Alexa";
  };
}
