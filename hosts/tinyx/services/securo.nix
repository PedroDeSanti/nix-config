# Securo (usesecuro.com): self-hosted personal finance for the household and friends.
# Public at https://securo.desanti.dev (tunnel), private at securo.lab.desanti.dev.
#
# Runs upstream's own docker-compose.prod.yml, pinned to a release and fetched by hash,
# plus a small override generated here: pinned image tags, state as bind mounts under
# /srv/securo, the frontend published on loopback only, memory limits, and the
# production URL. Nothing in the app itself is changed. Upgrading = bump `version`,
# refresh the compose hash, switch.
#
# Secrets (SECRET_KEY, POSTGRES_PASSWORD) live in /etc/secrets/securo.env. Postgres
# runs on the NVMe (never on the DRAM-less A400). A daily pg_dump lands in
# /srv/securo/backups, picked up by btrbk and restic like everything under /srv.
{ config, pkgs, lib, ... }:
let
  version = "0.15.1";
  stateDir = "/srv/securo";
  frontendPort = 3132;
  publicUrl = "https://securo.desanti.dev";

  upstreamCompose = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/securo-finance/securo/v${version}/docker-compose.prod.yml";
    hash = "sha256-ahrUa2QpStj5P92ORqsgC9mhFS2/1VKmQpv4hLHA24c=";
  };

  # Raw YAML rather than a generated attrset: the `!override` / `!reset` tags are how
  # compose replaces (instead of appending to) the upstream `ports` lists.
  override = pkgs.writeText "securo-override.yml" ''
    x-env: &env
      FRONTEND_URL: ${publicUrl}
      WEBAUTHN_RP_ID: desanti.dev
      # cloudflared -> Caddy -> frontend nginx -> backend
      TRUSTED_PROXY_HOPS: "3"
      DATABASE_URL: postgresql+asyncpg://postgres:''${POSTGRES_PASSWORD}@db:5432/securo

    services:
      db:
        image: docker.io/pgvector/pgvector:pg16
        environment:
          POSTGRES_PASSWORD: ''${POSTGRES_PASSWORD}
        mem_limit: 512m
      redis:
        image: docker.io/library/redis:8-alpine
        mem_limit: 128m
      backend:
        image: ghcr.io/securo-finance/securo-backend:${version}
        environment: *env
        ports: !reset []
        mem_limit: 768m
      celery-worker:
        image: ghcr.io/securo-finance/securo-backend:${version}
        environment: *env
        mem_limit: 768m
      celery-beat:
        image: ghcr.io/securo-finance/securo-backend:${version}
        environment: *env
        mem_limit: 256m
      frontend:
        image: ghcr.io/securo-finance/securo-frontend:${version}
        environment:
          FRONTEND_URL: ${publicUrl}
        ports: !override
          - "127.0.0.1:${toString frontendPort}:8080"
        mem_limit: 128m

    volumes:
      pgdata:
        driver_opts: { type: none, o: bind, device: ${stateDir}/pgdata }
      attachments:
        driver_opts: { type: none, o: bind, device: ${stateDir}/attachments }
      agent_knowledge:
        driver_opts: { type: none, o: bind, device: ${stateDir}/agent_knowledge }
      agent_embedding_models:
        driver_opts: { type: none, o: bind, device: ${stateDir}/embedding_models }
  '';

  docker = lib.getExe config.virtualisation.docker.package;
  # --project-directory makes upstream's relative `./secrets` resolve under /srv/securo.
  compose = "${docker} compose -p securo --project-directory ${stateDir} -f ${upstreamCompose} -f ${override} --env-file /etc/secrets/securo.env";
in
{
  systemd.tmpfiles.rules = map (d: "d ${stateDir}/${d} 0750 root root -") [
    "" "pgdata" "attachments" "agent_knowledge" "embedding_models" "secrets" "backups"
  ];

  systemd.services.securo = {
    description = "Securo (docker compose stack)";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ upstreamCompose override ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "10min";
      ExecStart = "${compose} up -d --remove-orphans --quiet-pull";
      ExecStop = "${compose} down";
    };
  };

  # Daily logical backup; keeps two weeks locally, restic keeps the rest.
  systemd.services.securo-backup = {
    description = "Securo Postgres dump";
    after = [ "securo.service" ];
    requires = [ "securo.service" ];
    path = [ pkgs.gzip pkgs.findutils pkgs.coreutils ];
    script = ''
      set -euo pipefail
      ${compose} exec -T db pg_dump -U postgres --clean --if-exists securo \
        | gzip > ${stateDir}/backups/securo-$(date +%F).sql.gz.tmp
      mv ${stateDir}/backups/securo-$(date +%F).sql.gz.tmp ${stateDir}/backups/securo-$(date +%F).sql.gz
      find ${stateDir}/backups -name "securo-*.sql.gz" -mtime +14 -delete
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.securo-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:30"; Persistent = true; RandomizedDelaySec = "10m"; };
  };

  tinyx.services.securo = {
    name = "Securo";
    subdomain = "securo";
    port = frontendPort;
    public = true;
    group = "Apps";
    order = 10;
    icon = "sh-securo";
    description = "Finanças pessoais, para a casa e amigos";
  };
}
