# Homepage (gethomepage.dev): the index of everything on tinyx, at https://lab.desanti.dev.
# Private tier only (tailnet + LAN).
#
# Cards are not listed here. Each service module declares its own card under
# `tinyx.homepage.groups.<Group>`, so a service appears on the page exactly when its
# module is imported. This file assembles the groups and holds the page-level settings.
#
# Secrets for widgets (AdGuard password, Home Assistant token) come from
# /etc/secrets/homepage.env as HOMEPAGE_VAR_* and are referenced as {{HOMEPAGE_VAR_*}}.
{ config, lib, ... }:
let
  cfg = config.tinyx.homepage;
  # Fixed display order; any other group lands after these.
  order = [ "Casa" "Apps" "Infra" ];
  groups = order ++ lib.filter (g: !(lib.elem g order)) (lib.attrNames cfg.groups);
in
{
  options.tinyx.homepage.groups = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.attrs);
    default = { };
    description = "Homepage cards keyed by group. Service modules append their own card.";
  };

  config = {
    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;
      allowedHosts = "lab.desanti.dev,localhost:8082,127.0.0.1:8082";
      environmentFiles = [ "/etc/secrets/homepage.env" ];

      settings = {
        title = "tinyx";
        # UI strings in English: the pt locale renders uptime as "CIMA". Card texts are ours.
        language = "en";
        theme = "dark";
        color = "slate";
        headerStyle = "clean";
        statusStyle = "dot";
        target = "_self";
        hideVersion = true;
        useEqualHeights = true;
        layout = lib.genAttrs groups (_: { style = "row"; columns = 3; });
      };

      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            cputemp = true;
            uptime = true;
            units = "metric";
            disk = [ "/" "/mnt/data" ];
          };
        }
        {
          datetime = {
            text_size = "xl";
            format = { dateStyle = "long"; timeStyle = "short"; hour12 = false; };
          };
        }
      ];

      bookmarks = [
        {
          Links = [
            { Cloudflare = [ { abbr = "CF"; href = "https://dash.cloudflare.com"; icon = "cloudflare.png"; } ]; }
            { Tailscale = [ { abbr = "TS"; href = "https://login.tailscale.com/admin/machines"; icon = "tailscale.png"; } ]; }
            { "nix-config" = [ { abbr = "GH"; href = "https://github.com/PedroDeSanti/nix-config"; icon = "github.png"; } ]; }
          ];
        }
      ];

      services = lib.filter (g: g != null)
        (map (g: if cfg.groups ? ${g} then { ${g} = cfg.groups.${g}; } else null) groups);
    };

    services.caddy.virtualHosts."lab.desanti.dev".extraConfig = ''
      tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      }
      reverse_proxy 127.0.0.1:8082
    '';
  };
}
