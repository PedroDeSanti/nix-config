# Reverse proxy for both tiers of names:
#   *.lab.desanti.dev  - private. DNS points at the tailnet IP; HTTPS with a wildcard
#                        certificate obtained through the Cloudflare DNS-01 challenge.
#   *.desanti.dev      - public. Arrives over the Cloudflare Tunnel on :8080 (plain HTTP,
#                        loopback only). Unknown names get the 404 page.
{ pkgs, ... }:
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
      "*.lab.desanti.dev" = {
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }

          @ha host ha.lab.desanti.dev
          handle @ha {
            reverse_proxy 127.0.0.1:8123
          }

          @z2m host z2m.lab.desanti.dev
          handle @z2m {
            reverse_proxy 127.0.0.1:8099
          }

          @matter host matter.lab.desanti.dev
          handle @matter {
            reverse_proxy 127.0.0.1:8482
          }

          @adguard host adguard.lab.desanti.dev
          handle @adguard {
            reverse_proxy 127.0.0.1:3000
          }

          handle {
            import not-found
          }
        '';
      };

      # Public tier, fed by the tunnel on :8080. Services are `@name host name.desanti.dev`
      # + handle blocks, like the private tier; anything else is a 404.
      "http://:8080" = {
        extraConfig = ''
          @ha host ha.desanti.dev
          handle @ha {
            reverse_proxy 127.0.0.1:8123
          }

          handle {
            import not-found
          }
        '';
      };
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
}
