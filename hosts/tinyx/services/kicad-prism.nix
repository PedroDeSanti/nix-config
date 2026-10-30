# KiCAD Prism (github.com/krishna-swaroop/KiCAD-Prism): browser review of the team's
# KiCad boards straight from Git. Public at https://prism.desanti.dev (tunnel), private
# at prism.lab.desanti.dev.
#
# Runs upstream's release bundle as is: its pull-only compose.yml and its .env.example,
# which pins the Prism images by digest. On top of that, a config env written here
# (public URL, login methods, resource ceilings sized for an 8 GB box) and the secrets
# env, layered in that order, plus a small override: state as bind mounts under
# /srv/kicad-prism and the env files above. Upgrading = bump `version`, refresh the
# bundle hash, read the release's UPGRADES.md, switch.
#
# Secrets (POSTGRES_PASSWORD, SESSION_SECRET, bootstrap admin, Google OIDC client) live
# in /etc/secrets/kicad-prism.env. A daily pg_dump lands in /srv/kicad-prism/backups;
# Postgres data, Git checkouts and SSH state are all under /srv, so btrbk and restic
# pick them up.
{ config, pkgs, lib, ... }:
let
  version = "4.0.0-alpha";
  stateDir = "/srv/kicad-prism";
  frontendPort = 3140;
  publicUrl = "https://prism.desanti.dev";

  bundle = pkgs.fetchzip {
    url = "https://github.com/krishna-swaroop/KiCAD-Prism/releases/download/v${version}/kicad-prism-v${version}-linux-amd64.tar.gz";
    hash = "sha256-jo1Ws3rqCnS0oo+nIJgZXTFZ9g2Et6fNbFMTtt+VrYE=";
  };

  # Upstream defaults assume 16+ GB and many cores. One API worker and one job at a
  # time keeps Prism next to Home Assistant and Securo; a job that outgrows its
  # ceiling gets OOM-killed inside its container and nothing else.
  settings = pkgs.writeText "kicad-prism-config.env" ''
    WORKSPACE_NAME=Team Micras
    PUBLIC_BASE_URL=${publicUrl}
    CORS_ORIGINS_STR=${publicUrl},https://prism.lab.desanti.dev
    PRISM_HTTP_PORT=${toString frontendPort}

    AUTH_ENABLED=true
    PASSWORD_AUTH_ENABLED=true
    OIDC_PROVIDER_NAME=Google
    OIDC_SCOPES=openid email profile
    IMPORT_ALLOWED_HOSTS_STR=github.com

    UVICORN_WORKERS=1
    PRISM_BACKEND_CPU_LIMIT=2.0
    PRISM_BACKEND_MEMORY_LIMIT=1g
    PRISM_WORKER_CPU_LIMIT=4.0
    PRISM_WORKER_MEMORY_LIMIT=2g
    CATALOG_WORKER_CPU_LIMIT=2.0
    CATALOG_WORKER_MEMORY_LIMIT=1g
    PRISM_WORKER_CONCURRENCY=1
    CATALOG_WORKER_CONCURRENCY=1
    PRISM_SEMANTIC_COMPILE_SLOTS=1
    PRISM_DESIGN_COMPARE_MAX_REVISION_WORKERS=1
    PRISM_DESIGN_COMPARE_MAX_INITIAL_WORKERS=1
    PRISM_DESIGN_COMPARE_MAX_PCB_WORKERS=1
    PRISM_DATABASE_POOL_MAX_SIZE=4
    PRISM_WORKER_DATABASE_POOL_MAX_SIZE=3
    CATALOG_WORKER_DATABASE_POOL_MAX_SIZE=2
  '';
  envFiles = [ "${bundle}/.env.example" "${settings}" "/etc/secrets/kicad-prism.env" ];

  override = pkgs.writeText "kicad-prism-override.yml" ''
    x-env: &env
      env_file: !override [ ${lib.concatStringsSep ", " envFiles} ]

    services:
      postgres:
        mem_limit: 256m
      backend: *env
      catalog-worker: *env
      prism-worker: *env
      frontend:
        mem_limit: 128m

    volumes:
      prism-postgres-data:
        driver_opts: { type: none, o: bind, device: ${stateDir}/pgdata }
  '';

  docker = lib.getExe config.virtualisation.docker.package;
  # --project-directory makes upstream's relative ./data resolve under /srv/kicad-prism.
  compose = "${docker} compose -p kicad-prism --project-directory ${stateDir} -f ${bundle}/compose.yml -f ${override} "
    + lib.concatMapStringsSep " " (f: "--env-file ${f}") envFiles;
in
{
  # postgres:17-alpine runs as uid 70 and wants its data dir 0700 (see securo.nix for
  # what a wrong owner here does after an unattended switch). The frontend's nginx
  # reads data/projects unprivileged, hence 0755 on the way there.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -"
    "d ${stateDir}/data 0755 root root -"
    "d ${stateDir}/data/projects 0755 root root -"
    "d ${stateDir}/data/ssh 0700 root root -"
    "d ${stateDir}/backups 0750 root root -"
    "d ${stateDir}/pgdata 0700 70 70 -"
  ];

  systemd.services.kicad-prism = {
    description = "KiCAD Prism (docker compose stack)";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ bundle settings override ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # First pull is several GB (the backend image is built on kicad/kicad).
      TimeoutStartSec = "30min";
      ExecStart = "${compose} up -d --remove-orphans --quiet-pull";
      ExecStop = "${compose} down";
    };
  };

  # Daily logical backup; keeps two weeks locally, restic keeps the rest.
  systemd.services.kicad-prism-backup = {
    description = "KiCAD Prism Postgres dump";
    after = [ "kicad-prism.service" ];
    requires = [ "kicad-prism.service" ];
    path = [ pkgs.gzip pkgs.findutils pkgs.coreutils ];
    script = ''
      set -euo pipefail
      ${compose} exec -T postgres pg_dump -U kicad_prism --clean --if-exists kicad_prism \
        | gzip > ${stateDir}/backups/kicad-prism-$(date +%F).sql.gz.tmp
      mv ${stateDir}/backups/kicad-prism-$(date +%F).sql.gz.tmp ${stateDir}/backups/kicad-prism-$(date +%F).sql.gz
      find ${stateDir}/backups -name "kicad-prism-*.sql.gz" -mtime +14 -delete
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.kicad-prism-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:40"; Persistent = true; RandomizedDelaySec = "10m"; };
  };

  tinyx.services.kicad-prism = {
    name = "KiCAD Prism";
    subdomain = "prism";
    port = frontendPort;
    public = true;
    group = "Apps";
    order = 20;
    icon = "si-kicad";
    description = "Placas da equipe, direto do Git";
    monitor = "http://127.0.0.1:${toString frontendPort}/healthz";
  };
}
