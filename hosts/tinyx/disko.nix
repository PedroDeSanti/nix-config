# Disk layout for tinyx. Applied once with `disko --mode destroy,format,mount`;
# after that it only generates fileSystems/swapDevices.
#
# Devices by /dev/disk/by-id, never /dev/sdX: with the installer USB plugged in,
# "sda" may be the Ventoy stick.
let
  btrfsOpts = [ "compress=zstd" "noatime" ];
  # Boot must not depend on the data disk; don't wait 90 s for a dead one.
  dadosOpts = btrfsOpts ++ [ "nofail" "x-systemd.device-timeout=15s" ];
in
{
  disko.devices.disk = {

    # Micron 2450 NVMe 512 GB: system
    nvme = {
      type = "disk";
      # Namespaced form (`_1`); the unsuffixed alias is deprecated in systemd 260.
      device = "/dev/disk/by-id/nvme-Micron_2450_NVMe_512GB_22243EC9CAD6_1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          swap = {
            size = "8G";
            content = {
              type = "swap";
              randomEncryption = true;   # fresh dm-crypt key every boot
              discardPolicy = "once";    # fstrim does not cover swap
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" "-L" "tinyx" ];
              # Flat layout: one subvolume per snapshot/backup policy.
              subvolumes = {
                "/@"          = { mountpoint = "/";               mountOptions = btrfsOpts; };
                "/@nix"       = { mountpoint = "/nix";            mountOptions = btrfsOpts; };
                "/@home"      = { mountpoint = "/home";           mountOptions = btrfsOpts; };
                "/@srv"       = { mountpoint = "/srv";            mountOptions = btrfsOpts; }; # container state: snapshot + backup
                "/@docker"    = { mountpoint = "/var/lib/docker"; mountOptions = btrfsOpts; }; # images/layers: regenerable, excluded
                "/@log"       = { mountpoint = "/var/log";        mountOptions = btrfsOpts; }; # survives a rollback of /
                "/@snapshots" = { mountpoint = "/.snapshots";     mountOptions = btrfsOpts; };
              };
            };
          };
        };
      };
    };

    # Kingston A400 SATA 480 GB: cold data (DRAM-less, no databases here)
    dados = {
      type = "disk";
      device = "/dev/disk/by-id/ata-KINGSTON_SA400S37480G_50026B768324FE9C";
      content = {
        type = "gpt";
        partitions.dados = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" "-L" "dados" ];
            subvolumes = {
              # A subvolume rather than the top-level: the top-level cannot be snapshotted.
              "/@dados"     = { mountpoint = "/mnt/dados";            mountOptions = dadosOpts; };
              "/@snapshots" = { mountpoint = "/mnt/dados/.snapshots"; mountOptions = dadosOpts; };
            };
          };
        };
      };
    };
  };
}
