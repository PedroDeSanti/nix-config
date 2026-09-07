# Cloudflare Tunnel: outbound-only connection to Cloudflare's edge. Public hostnames
# (`*.desanti.dev`) reach Caddy through it; no inbound port on the router.
# Created once with `cloudflared tunnel login && cloudflared tunnel create tinyx`.
{ ... }:
let
  tunnelId = "c862027a-61d3-470c-8cf9-7bfb2ec07e3e";
in
{
  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = "/etc/secrets/cloudflared-tinyx.json";
      # Everything lands on Caddy's plain-HTTP listener; the tunnel itself is encrypted.
      ingress."*.desanti.dev" = "http://127.0.0.1:8080";
      default = "http_status:404";
    };
  };
}
