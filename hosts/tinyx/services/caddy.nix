# Reverse proxy for both tiers of names:
#   *.lab.desanti.dev  - private. DNS points at the tailnet IP; HTTPS with a wildcard
#                        certificate obtained through the Cloudflare DNS-01 challenge.
#   *.desanti.dev      - public. Arrives over the Cloudflare Tunnel on :8080 (plain HTTP,
#                        loopback only). Unknown names get the 404 page.
{ pkgs, ... }:
{
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

          handle {
            import not-found
          }
        '';
      };

      # Public tier, fed by the tunnel. Services get their own `http://name.desanti.dev`
      # blocks; anything else is a 404.
      "http://:8080" = {
        extraConfig = ''
          import not-found
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
