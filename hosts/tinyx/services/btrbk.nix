# btrbk: hourly btrfs snapshots of the stateful subvolumes, mirrored to the A400.
# Snapshots protect against "oops" (bad upgrade, deleted file); the send/receive copy
# protects against the NVMe dying. Neither is off-site: that is Restic's job.
{ ... }:
{
  services.btrbk.instances.local = {
    onCalendar = "hourly";
    settings = {
      timestamp_format = "long";
      # Skip the snapshot when nothing changed since the last one (generation check).
      snapshot_create = "onchange";
      # Ratios chosen for a homelab: 2 days of hourlies to undo a bad container
      # upgrade, 2 weeks of dailies, 2 months of weeklies. The mirror keeps more.
      snapshot_preserve_min = "2d";
      snapshot_preserve = "48h 14d 8w";
      target_preserve_min = "no";
      target_preserve = "14d 10w 6m";

      volume."/" = {
        snapshot_dir = ".snapshots";
        target = "send-receive /mnt/data/.snapshots";
        subvolume = {
          home = { };
          srv = { };
        };
      };
    };
  };
}
