# Restic: nightly off-site backup of /home and /srv to Google Drive (via rclone).
# btrbk covers local history and the NVMe dying; this covers the house burning down.
# Backs up a fresh read-only btrfs snapshot, not the live tree: consistent, and a fixed
# path lets restic find the parent snapshot and skip unchanged files.
#
# Secrets (not in the repo): /etc/secrets/rclone.conf (OAuth token, scope drive.file)
# and /etc/secrets/restic.pass (also in Bitwarden — without it the repo is noise).
{ pkgs, ... }:
let
  src = "/.snapshots/restic";
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
in
{
  services.restic.backups.gdrive = {
    repository = "rclone:gdrive:tinyx-backup";
    rcloneConfigFile = "/etc/secrets/rclone.conf";
    passwordFile = "/etc/secrets/restic.pass";
    initialize = true;

    paths = [ "${src}/home" "${src}/srv" ];
    exclude = [
      "${src}/home/*/.cache"
      "${src}/home/*/.local/share/Trash"
    ];
    extraBackupArgs = [ "--exclude-caches" ];

    backupPrepareCommand = ''
      set -eu
      mkdir -p ${src}
      # Leftovers from a run that died mid-way.
      for s in home srv; do
        [ -d ${src}/$s ] && ${btrfs} subvolume delete ${src}/$s
      done
      ${btrfs} subvolume snapshot -r /home ${src}/home
      ${btrfs} subvolume snapshot -r /srv  ${src}/srv
    '';
    backupCleanupCommand = ''
      ${btrfs} subvolume delete ${src}/home ${src}/srv
    '';

    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 14"
      "--keep-weekly 8"
      "--keep-monthly 12"
      "--keep-yearly 3"
    ];
    # Structural check every run; re-download a random 2 % of the data each night
    # (~50 % of the repo verified per month at Drive bandwidth cost only).
    checkOpts = [ "--read-data-subset=2%" ];

    # Pruned packs must actually disappear, not sit in the Drive trash.
    rcloneOptions = {
      drive-use-trash = "false";
      drive-chunk-size = "64M";
    };
  };
}
