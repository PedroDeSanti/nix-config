# AdGuard Home: the house DNS. Split-horizon for `*.lab.desanti.dev`: clients on the LAN get
# 192.168.0.210 and reach Caddy directly (no tunnel, works without internet); the public
# record keeps the tailnet IP for everyone else. Upstreams over DNS-over-HTTPS.
#
# The router hands this out via DHCP (DNSv4 page: primary 192.168.0.210, secondary the ISP
# resolver). Never use 1.1.1.1/8.8.8.8/9.9.9.9 there: Chrome auto-upgrades to that provider's
# DoH and bypasses us. Ad-blocking: HaGeZi Pro + TIF + AdGuard DNS filter.
# Web UI on 127.0.0.1:3000, reached through Caddy (adguard.lab.desanti.dev); login santi,
# password in /etc/secrets/adguard-ui.pass (only its bcrypt hash lives here).
#
# Config is fully declarative (mutableSettings = false): the YAML is regenerated on every
# start and UI changes do not survive a restart. Change things here.
{ ... }:
{
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    mutableSettings = false;
    settings = {
      users = [ { name = "santi"; password = "$2y$10$moFBBsKUvKAe.0yP0gkBROMYlwNgbyDq9/BTLFMFByAzIDn/Z30K6"; } ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "https://dns.cloudflare.com/dns-query"
          "https://dns.quad9.net/dns-query"
        ];
        # Plain DNS, IPs only: resolves the DoH hostnames without depending on ourselves.
        bootstrap_dns = [ "1.1.1.1" "9.9.9.9" ];
        # Plain DNS safety net if both DoH upstreams are unreachable (this is the only
        # resolver the house gets from DHCP).
        fallback_dns = [ "1.1.1.1" "9.9.9.9" ];
        upstream_mode = "load_balance";
        cache_size = 4194304;
        cache_optimistic = true;
      };
      filtering = {
        protection_enabled = true;
        # Observed (not documented): rewrites only apply while the filtering engine is on.
        filtering_enabled = true;
        # `enabled` must be explicit (schema >= 29 defaults it to false). The wildcard does
        # not cover the bare name, hence two entries. AAAA for these names returns empty.
        rewrites = [
          { domain = "*.lab.desanti.dev"; answer = "192.168.0.210"; enabled = true; }
          { domain = "lab.desanti.dev";   answer = "192.168.0.210"; enabled = true; }
        ];
      };
      # Blocklists from the built-in catalog (HostlistsRegistry ids), refreshed every 24 h.
      # One solid base list + a threat feed, not a stack of overlapping lists.
      filters = [
        { id = 1;  enabled = true; name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; }
        { id = 48; enabled = true; name = "HaGeZi Pro";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_48.txt"; }
        { id = 44; enabled = true; name = "HaGeZi Threat Intelligence Feeds";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_44.txt"; }
      ];
      # Allowlist: tracking redirectors behind promo/affiliate links, so links from e-mails
      # and Instagram keep opening.
      whitelist_filters = [
        { id = 45; enabled = true; name = "HaGeZi Allowlist Referral";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_45.txt"; }
      ];
      # Known false positives (hagezi/dns-blocklists#7174): the Itau app needs these.
      user_rules = [
        "@@||mobilepessoafisica.itau.com.br^"
        "@@||banner2.itau.com.br^"
      ];
      querylog = { enabled = true; interval = "168h"; };
      statistics = { enabled = true; interval = "24h"; };
    };
  };

  # AdGuard's permcheck wants the state dir at 0700; the module leaves systemd's 0755 default.
  systemd.services.adguardhome.serviceConfig.StateDirectoryMode = "0700";

  # DNS for the LAN; tailscale0 is already trusted. Exposure is controlled here, by
  # interface, rather than with allowed_clients (a client list would break the day the
  # router hands out our IPv6, whose prefix rotates).
  networking.firewall.interfaces.wlp2s0 = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };

  tinyx.services.adguardhome = {
    name = "AdGuard Home";
    subdomain = "adguard";
    port = 3000;
    group = "Infra";
    order = 10;
    icon = "adguard-home.png";
    description = "DNS da casa: split-horizon e bloqueio";
    widget = { type = "adguard"; url = "http://127.0.0.1:3000"; username = "santi"; password = "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}"; };
  };
}
