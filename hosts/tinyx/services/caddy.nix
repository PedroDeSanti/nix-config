# Reverse proxy for both tiers of names:
#   *.lab.desanti.dev  - private. DNS points at the tailnet IP (AdGuard rewrites it to the
#                        LAN IP at home); HTTPS with a wildcard certificate via DNS-01.
#   *.desanti.dev      - public. Arrives over the Cloudflare Tunnel on :8080 (plain HTTP,
#                        loopback only). Unknown names get the 404 page.
# Per-service routes are generated from `tinyx.services` (see registry.nix); nothing
# service-specific lives here.
{ config, pkgs, ... }:
{
  # HTTPS (and the HTTP redirect) on the LAN too: *.lab names resolve to the LAN IP at home.
  networking.firewall.interfaces.wlp2s0.allowedTCPPorts = [ 80 443 ];

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-PWadA5qr/gR2qDcT8l8u1Xku7LM2HIfWTLOkzezCYy0=";
    };
    # CLOUDFLARE_API_TOKEN for the DNS-01 challenge (DNS:Edit on desanti.dev only).
    environmentFile = "/etc/secrets/cloudflare-dns.env";

    globalConfig = ''
      email phmartinsanti@gmail.com
    '';

    virtualHosts = {
      # Private tier: one wildcard certificate, host-based routing inside.
      "*.lab.desanti.dev".extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }

        ${config.tinyx.caddy.labRoutes}
        handle {
          import not-found
        }
      '';

      # Public tier, fed by the tunnel on :8080.
      "http://:8080".extraConfig = ''
        ${config.tinyx.caddy.publicRoutes}
        handle {
          import not-found
        }
      '';
    };

    extraConfig = ''
      (not-found) {
        root * ${./caddy}
        rewrite * /404.html
        file_server {
          status 404
        }
      }
    '';
  };

  tinyx.services.caddy = {
    name = "Caddy";
    group = "Infra";
    order = 30;
    icon = "caddy.png";
    description = "Proxy reverso, *.lab e tunel";
    monitor = "http://127.0.0.1:8080";
  };
}
