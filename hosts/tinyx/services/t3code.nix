# T3 Code: web/mobile control plane for Claude Code sessions on this machine.
#
# The server itself is a *user* service (home/santi/common/optional/t3code.nix) because
# it drives the `claude` login stored in ~/.claude. This module holds the system side:
# the packages, the Caddy/Homepage entry, lingering, and the daily update.
#
# Published only on the private tier (t3.lab.desanti.dev). A pairing link hands out
# Claude, the repos and a shell; it must never go through the Cloudflare Tunnel.
# `tailscale serve` is deliberately not used: it would intercept :443 on the tailnet
# IP inside tailscaled and cut Caddy off from every *.lab request coming over
# Tailscale (tailscale/tailscale#7763).
{ config, pkgs, lib, inputs, ... }:
let
  port = 3773;
  flake = "/home/santi/nix-config";
in
{
  # t3code and claude-code release every few days; the 26.05 branch is months behind
  # (t3code 0.0.24 vs 0.0.40) and the phone app refuses mismatched servers. Take just
  # these two from nixos-unstable; everything else stays on the stable branch.
  nixpkgs.overlays = [
    (final: prev:
      let
        unstable = import inputs.nixpkgs-unstable {
          inherit (prev.stdenv.hostPlatform) system;
          # claude-code is unfree; the check runs inside this package set, not the stable one.
          config.allowUnfreePredicate = p: lib.elem (lib.getName p) [ "claude-code" ];
        };
      in
      {
        claude-code = unstable.claude-code;
        # enableClaude puts `claude` on the wrapper's PATH so T3 finds it without relying
        # on the user service's environment. git/gh come along by default.
        t3code = unstable.t3code.override { enableClaude = true; };
      })
  ];

  # The user manager (and with it t3code.service) must run without a login session.
  users.users.santi.linger = true;

  tinyx.services.t3code = {
    name = "T3 Code";
    subdomain = "t3";
    inherit port;
    group = "Apps";
    order = 20;
    icon = "sh-claude";
    description = "Claude Code remoto";
  };

  # "Always latest": bump only the nixpkgs-unstable input, switch, commit the lock.
  # Only runs on a clean working tree.
  # Refuses to proceed when the heavy packages are not in cache.nixos.org yet (a local
  # t3code build is a full pnpm+electron build; not on 8 GB). A failed switch restores
  # the previous lock. Runs as santi so the commit has the right author; nh escalates
  # itself through sudo, which wheel has without a password.
  systemd.services.devtools-update = {
    description = "Update t3code/claude-code from nixpkgs-unstable";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git pkgs.nix pkgs.nh pkgs.coreutils "/run/wrappers" ];
    serviceConfig = {
      Type = "oneshot";
      User = "santi";
      WorkingDirectory = flake;
    };
    script = ''
      set -euo pipefail
      # The switch deploys the whole working tree, so any uncommitted change (not just
      # the lock) would go live unreviewed at night. Skip until everything is committed.
      if [ -n "$(git status --porcelain)" ]; then
        echo "working tree has uncommitted changes; not switching"; exit 0
      fi
      nix flake update nixpkgs-unstable
      if git diff --quiet -- flake.lock; then echo "nixpkgs-unstable unchanged"; exit 0; fi
      restore() { git checkout -- flake.lock; }
      trap restore ERR
      # claude-code is unfree, so it is never on cache.nixos.org, but building it is just
      # unpacking a prebuilt binary. Only the pnpm+electron build of t3code has to be cached.
      out=$(nix eval --raw ".#nixosConfigurations.tinyx.pkgs.t3code.unwrapped.outPath")
      if ! nix path-info --store https://cache.nixos.org "$out" >/dev/null 2>&1; then
        echo "t3code not in cache.nixos.org yet; keeping the current lock"; restore; exit 0
      fi
      nh os switch . --no-nom   # escalates via sudo internally; refuses to start as root
      cc=$(nix eval --raw ".#nixosConfigurations.tinyx.pkgs.claude-code.version")
      t3=$(nix eval --raw ".#nixosConfigurations.tinyx.pkgs.t3code.version")
      git commit -q -m "chore(tinyx): bump nixpkgs-unstable (claude-code $cc, t3code $t3)" -- flake.lock
      echo "updated: claude-code $cc, t3code $t3"
    '';
  };
  systemd.timers.devtools-update = {
    wantedBy = [ "timers.target" ];
    # After restic (03:00-03:40). Switching restarts t3code.service, so keep it at night.
    timerConfig = { OnCalendar = "04:30"; RandomizedDelaySec = "15m"; Persistent = true; };
  };
}
