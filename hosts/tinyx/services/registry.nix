# Service registry: the one place a service says who it is. Each module declares
# `tinyx.services.<id>` and this file derives everything that depends on the address:
#   - the Caddy route on the private tier   https://<subdomain>.lab.desanti.dev
#   - the Caddy route on the public tier    https://<subdomain>.desanti.dev  (public = true)
#   - the Homepage card (group, icon, link, status probe, widget)
# DNS and certificates are wildcards, so a new service needs no records.
{ config, lib, ... }:
let
  cfg = config.tinyx.services;
  labDomain = "lab.desanti.dev";
  publicDomain = "desanti.dev";

  routed = lib.filterAttrs (_: s: s.subdomain != null) cfg;
  route = host: s: ''
    @${s.subdomain} host ${host}
    handle @${s.subdomain} {
      reverse_proxy 127.0.0.1:${toString s.port}
    }
  '';
  routes = domain: services:
    lib.concatStrings (lib.mapAttrsToList (_: s: route "${s.subdomain}.${domain}" s) services);

  card = s: {
    ${s.name} = {
      inherit (s) icon description;
    }
    // lib.optionalAttrs (s.monitor != null || s.port != null) {
      siteMonitor = if s.monitor != null then s.monitor else "http://127.0.0.1:${toString s.port}";
    }
    // lib.optionalAttrs (s.subdomain != null) { href = "https://${s.subdomain}.${labDomain}"; }
    // lib.optionalAttrs (s.widget != { }) { widget = s.widget; };
  };
  byGroup = lib.groupBy (s: s.group) (lib.attrValues cfg);
  sorted = lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name));
in
{
  options.tinyx = {
    services = lib.mkOption {
      default = { };
      description = "Services running on tinyx; drives Caddy routes and the Homepage.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; description = "Display name."; };
          subdomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Label under lab.desanti.dev (and desanti.dev if public). null = no web UI.";
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "Loopback port Caddy proxies to.";
          };
          public = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Also reachable from the internet through the Cloudflare Tunnel.";
          };
          group = lib.mkOption { type = lib.types.enum [ "Casa" "Infra" ]; description = "Homepage group."; };
          order = lib.mkOption { type = lib.types.int; default = 50; description = "Position within the group."; };
          icon = lib.mkOption { type = lib.types.str; description = "dashboard-icons file name."; };
          description = lib.mkOption { type = lib.types.str; description = "One line under the card title."; };
          monitor = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Status probe URL; defaults to http://127.0.0.1:<port>.";
          };
          widget = lib.mkOption { type = lib.types.attrs; default = { }; description = "Homepage widget config."; };
        };
      });
    };
    caddy.labRoutes = lib.mkOption { type = lib.types.lines; readOnly = true; description = "Generated private-tier routes."; };
    caddy.publicRoutes = lib.mkOption { type = lib.types.lines; readOnly = true; description = "Generated public-tier routes."; };
  };

  config = {
    assertions = lib.mapAttrsToList (id: s: {
      assertion = s.subdomain == null || s.port != null;
      message = "tinyx.services.${id}: a subdomain needs a port to proxy to.";
    }) cfg;

    tinyx.caddy.labRoutes = routes labDomain routed;
    tinyx.caddy.publicRoutes = routes publicDomain (lib.filterAttrs (_: s: s.public) routed);
    tinyx.homepage.groups = lib.mapAttrs (_: services: map card (sorted services)) byGroup;
  };
}
