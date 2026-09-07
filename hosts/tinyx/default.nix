# tinyx: headless homelab on a ThinkCentre M720q (i5-9400T, 8 GB, Wi-Fi only).
{ config, pkgs, lib, ... }:

{
  # ── Boot ────────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;   # ~60-90 MB per generation; fits a 1 GiB ESP
    # Without a BIOS password, editor=false protects nothing (USB boot is open)
    # and would remove the only console rescue path (systemd.unit=rescue.target).
    editor = true;
    memtest86.enable = true;
  };
  boot.loader.timeout = 2;
  boot.loader.efi.canTouchEfiVariables = true;
  # Headless: an initrd failure must drop to a shell, not to a locked emergency.target.
  boot.initrd.systemd.emergencyAccess = true;

  boot.kernelParams = [
    # zswap: compressed cache in front of the swap partition.
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=25"
    "zswap.shrinker_enabled=1"
    "panic=10"   # reboot 10 s after a kernel panic; the watchdog below covers hangs
  ];
  boot.kernelModules = [ "coretemp" "iTCO_wdt" ];
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "2min";
  };
  boot.tmp.cleanOnBoot = true;   # /tmp on disk; 8 GB of RAM is too little for tmpfs

  # Always-on Wi-Fi: power_scheme=1 disables iwlmvm power saving.
  boot.extraModprobeConfig = ''
    options iwlmvm power_scheme=1
  '';

  hardware.enableRedistributableFirmware = true;   # iwlwifi firmware, Intel microcode

  # ── Network ─────────────────────────────────────────────────────────────────────
  networking.hostName = "tinyx";
  # The ISP router has no DHCP reservations. Its pool is shrunk to .2-.201 and
  # wlp2s0 gets a static address outside it. eno1 stays on DHCP as a cable rescue path.
  networking.useDHCP = true;
  networking.interfaces.wlp2s0.ipv4.addresses = [ { address = "192.168.0.210"; prefixLength = 24; } ];
  networking.defaultGateway = { address = "192.168.0.1"; interface = "wlp2s0"; };
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" ];   # the router does not serve DNS
  networking.dhcpcd.denyInterfaces = [ "docker*" "br-*" "veth*" ];

  networking.wireless = {
    enable = true;
    # PSK lives outside the store: /etc/secrets/wifi.conf holds `psk_danke=<password>`.
    secretsFile = "/etc/secrets/wifi.conf";
    # Same router, same password: "Danke" is the 5 GHz radio, "Bitte" the 2.4 GHz fallback.
    networks."Danke" = { pskRaw = "ext:psk_danke"; priority = 10; };
    networks."Bitte" = { pskRaw = "ext:psk_danke"; priority = 1; };
  };
  # wpa_supplicant runs unprivileged since 26.05, so the secrets file must be group-readable.
  systemd.tmpfiles.rules = [
    "d /etc/secrets 0755 root root - -"
    "z /etc/secrets/wifi.conf 0640 root wpa_supplicant - -"
    "z /etc/secrets/santi.hash 0600 root root - -"
  ];

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  # ── Access ──────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    authorizedKeysInHomedir = false;   # only keys declared here are valid
    settings = {
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;   # PasswordAuthentication alone leaves PAM open
      PasswordAuthentication = false;
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;   # UDP 41641 for direct connections instead of DERP relays
    # MagicDNS would replace networking.nameservers and forward to the tailnet's
    # global nameservers, which are unset; that broke all external resolution.
    extraSetFlags = [ "--accept-dns=false" ];
  };

  users.mutableUsers = false;
  # Root keeps a password for the local console only (sulogin refuses a locked root).
  users.users.root.hashedPasswordFile = "/etc/secrets/santi.hash";
  users.users.santi = {
    isNormalUser = true;
    uid = 1000;   # fixed so /srv ownership and container PUID/PGID survive a reinstall
    extraGroups = [ "wheel" "docker" ];
    hashedPasswordFile = "/etc/secrets/santi.hash";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDWCI3q/vTKqcuHTbIhIrF5HcccBnOT4oQBaGHM9myWe notebook -> tinyx"
    ];
  };
  # The SSH key is the security boundary; remote `nixos-rebuild --use-remote-sudo` needs this.
  security.sudo.wheelNeedsPassword = false;

  # ── Containers ──────────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    liveRestore = true;   # detached stacks survive a dockerd restart
    autoPrune = { enable = true; dates = "weekly"; randomizedDelaySec = "45min"; };
    daemon.settings = {
      # containerd image store instead of the legacy overlay2 graphdriver, which
      # Docker only supports on ext4/xfs.
      features."containerd-snapshotter" = true;
      # Published ports (-p) bypass the NixOS firewall (Docker writes to FORWARD,
      # nixos-fw filters INPUT). Binding to loopback keeps them local; only the
      # reverse proxy publishes. Per-container exceptions: `-p 0.0.0.0:53:53`,
      # `network_mode: host`.
      ip = "127.0.0.1";
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };
    };
  };
  virtualisation.oci-containers.backend = "docker";
  # With the systemd cgroup driver each container is a scope in system.slice, so
  # under memory pressure oomd kills the container (Docker restarts it) instead
  # of the kernel OOM killer picking a random target after minutes of thrashing.
  systemd.oomd.enableSystemSlice = true;
  # oomd picks by reclaim pressure, not size; keep it away from the services
  # that give us access to the machine.
  systemd.services = lib.genAttrs [ "docker" "sshd" "tailscaled" "wpa_supplicant" "dhcpcd" ]
    (_: { serviceConfig.ManagedOOMPreference = "avoid"; });
  # Second net, on a different signal (free RAM+swap, not PSI). Only fires once
  # zswap and the swap partition are both exhausted.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
    reportInterval = 0;
    extraArgs = [ "--avoid" "^(dockerd|containerd|containerd-shim.*|tailscaled|sshd|systemd.*|wpa_supplicant|dhcpcd)$" ];
  };

  # ── Storage ─────────────────────────────────────────────────────────────────────
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" "/mnt/dados" ];
  };
  services.fstrim.enable = true;
  services.smartd.enable = true;
  services.journald.extraConfig = "SystemMaxUse=500M";

  # ── Nix ─────────────────────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # ── System ──────────────────────────────────────────────────────────────────────
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
  };
  console.keyMap = "br-abnt2";

  programs.nix-ld.enable = true;   # loader for foreign binaries (VS Code Server, prebuilt tools)

  environment.systemPackages = with pkgs; [
    vim git tmux htop btop
    lm_sensors smartmontools
    pciutils usbutils ethtool dig
    kitty.terminfo   # SSH sessions from kitty set TERM=xterm-kitty
    iw
    ncdu iotop tcpdump
    compsize         # actual Btrfs compression ratio
  ];

  programs.nh = {
    enable = true;
    flake = "/home/santi/nix-config";
    clean = { enable = true; extraArgs = "--keep-since 7d --keep 5"; };
  };

  system.stateVersion = "26.05";   # never change after install
}
