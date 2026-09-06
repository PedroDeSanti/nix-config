# Layout de discos do tinyx. Aplicado uma vez com:
#   disko --mode destroy,format,mount ./disko.nix
# Depois disso este arquivo só serve para gerar fileSystems/swapDevices na config.
#
# Dispositivos por /dev/disk/by-id — nunca por /dev/sdX: com o pendrive plugado,
# "sda" pode ser o Ventoy.
let
  btrfsOpts = [ "compress=zstd" "noatime" ];
  # nofail: boot segue sem o A400; device-timeout: não espera 90 s por um disco morto.
  dadosOpts = btrfsOpts ++ [ "nofail" "x-systemd.device-timeout=15s" ];
in
{
  disko.devices.disk = {

    # ── Micron 2450 NVMe 512 GB — sistema ────────────────────────────────────
    nvme = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Micron_2450_NVMe_512GB_22243EC9CAD6_1";   # forma com namespace: a sem sufixo está marcada obsoleta no systemd 260
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
              mountOptions = [ "umask=0077" ];  # ESP não é world-readable (manual NixOS)
            };
          };
          swap = {
            size = "8G";
            content = {
              type = "swap";
              randomEncryption = true;   # chave aleatória por boot (dm-crypt, AES-NI): sem segredos em claro no swap
              discardPolicy = "once";    # TRIM no swapon (fstrim não cobre swap; sem isto a partição nunca é trimada)
              # zswap fica na frente desta partição (ver boot.kernelParams em configuration.nix)
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" "-L" "tinyx" ];
              # Layout flat: todos os subvolumes são filhos do top-level (subvolid 5).
              # Um subvolume por política de snapshot/backup diferente.
              subvolumes = {
                "/@"          = { mountpoint = "/";               mountOptions = btrfsOpts; };
                "/@nix"       = { mountpoint = "/nix";            mountOptions = btrfsOpts; };
                "/@home"      = { mountpoint = "/home";           mountOptions = btrfsOpts; };
                "/@srv"       = { mountpoint = "/srv";            mountOptions = btrfsOpts; }; # estado dos containers → snapshot + backup
                "/@docker"    = { mountpoint = "/var/lib/docker"; mountOptions = btrfsOpts; }; # imagens/layers → regenerável, fora de tudo
                "/@log"       = { mountpoint = "/var/log";        mountOptions = btrfsOpts; }; # sobrevive a rollback de /
                "/@snapshots" = { mountpoint = "/.snapshots";     mountOptions = btrfsOpts; }; # destino de snapshots de @ e @srv
              };
            };
          };
        };
      };
    };

    # ── Kingston A400 SATA 480 GB — dados frios ──────────────────────────────
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
              # @dados em vez de montar o top-level: o top-level não pode ser snapshotado.
              "/@dados"     = { mountpoint = "/mnt/dados";            mountOptions = dadosOpts; };
              "/@snapshots" = { mountpoint = "/mnt/dados/.snapshots"; mountOptions = dadosOpts; };
            };
          };
        };
      };
    };
  };
}
