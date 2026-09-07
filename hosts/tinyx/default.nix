# tinyx — configuração base (item 4 do briefing: SSH, rede, Tailscale, sensores, gc).
# Caddy e Restic/Backrest entram após o primeiro boot (precisam de domínio/segredos).
{ config, pkgs, lib, ... }:

{
  # ── Boot ────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;   # ~60–90 MB por geração; 10 cabem folgado em 1 GiB de ESP
    # editor=true: sem senha de BIOS/Secure Boot, editor=false não protege nada (boot por USB é livre) e
    # tiraria a única alavanca de resgate no console (systemd.unit=rescue.target). Fechar isso no BIOS.
    editor = true;
    memtest86.enable = true;   # entrada Memtest86+ (GPL) no menu de boot — pendência do briefing
  };
  boot.loader.timeout = 2;
  boot.loader.efi.canTouchEfiVariables = true;
  # Recuperação headless: sem isso, falha no initrd cai em emergency.target SEM shell (mesmo com teclado).
  boot.initrd.systemd.emergencyAccess = true;

  boot.kernelParams = [
    # zswap: cache comprimido na frente da partição de swap (ver Chris Down, 2026).
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=25"   # até 25 % da RAM (~2 GB) em páginas comprimidas
    "zswap.shrinker_enabled=1"    # evicta páginas frias para o disco antes de lotar
    "panic=10"                    # kernel panic → reboot em 10 s (não depender só do watchdog)
  ];
  boot.kernelModules = [ "coretemp" "iTCO_wdt" ];   # sensores por core; watchdog do PCH Intel
  # Kernel travado → reboot em 30 s (o BIOS já religa após queda de energia; isto cobre o hang).
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "2min";
  };
  boot.tmp.cleanOnBoot = true;           # /tmp em disco (8 GB de RAM não sobram para tmpfs)

  # Wi-Fi 24/7: power_scheme=1 = CAM (sempre acordado). iwlwifi.power_save já é off por default.
  boot.extraModprobeConfig = ''
    options iwlmvm power_scheme=1
  '';

  hardware.enableRedistributableFirmware = true;   # firmware do AC 8265 (iwlwifi) e microcode

  # ── Rede ────────────────────────────────────────────────────────────────────
  networking.hostName = "tinyx";
  # O Sagemcom da Claro não tem reserva por MAC. Pool DHCP encolhido para .2–.201 (CPEs=200) no roteador;
  # wlp2s0 fica ESTÁTICO fora do pool. eno1 continua em DHCP (useDHCP) = resgate por cabo.
  networking.useDHCP = true;
  networking.interfaces.wlp2s0.ipv4.addresses = [ { address = "192.168.0.210"; prefixLength = 24; } ];
  networking.defaultGateway = { address = "192.168.0.1"; interface = "wlp2s0"; };
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" ];
  networking.dhcpcd.denyInterfaces = [ "docker*" "br-*" "veth*" ];   # sem DHCP/IPv4LL nas bridges do Docker

  networking.wireless = {
    enable = true;
    # interfaces = [ ]: autodetecta a placa (não depende do nome wlp2s0 existir no kernel/systemd novos)
    # PSK fora do store: /etc/secrets/wifi.conf contém `psk_danke=<senha>` (modo 600).
    secretsFile = "/etc/secrets/wifi.conf";
    # SSID real = "Danke" (5 GHz); "Bitte" = rádio 2,4 GHz do mesmo roteador, mesma senha — fallback
    # se o 5 GHz cair. "Danke 1" era só o nome do perfil no NM do Ubuntu. priority maior = preferido.
    networks."Danke" = { pskRaw = "ext:psk_danke"; priority = 10; };
    networks."Bitte" = { pskRaw = "ext:psk_danke"; priority = 1; };
  };
  # NixOS 26.05: wpa_supplicant roda como usuário `wpa_supplicant` (hardening). O arquivo é
  # instalado 0600 root; esta regra ajusta dono/modo em cada boot, antes do serviço subir.
  systemd.tmpfiles.rules = [
    "d /etc/secrets 0755 root root - -"
    "z /etc/secrets/wifi.conf 0640 root wpa_supplicant - -"
    "z /etc/secrets/santi.hash 0600 root root - -"
  ];

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];   # tudo aberto só dentro da tailnet
  };

  # ── Acesso ──────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    # Só as chaves da config valem: ~/.ssh/authorized_keys é ignorado (por default o NixOS aceita os dois).
    authorizedKeysInHomedir = false;
    settings = {
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;   # só chave; a senha do santi serve apenas para console local
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;   # UDP 41641 → conexões diretas em vez de DERP
    # MagicDNS sobrescreve networking.nameservers e encaminha para os "global
    # nameservers" da tailnet; sem eles definidos, toda resolucao externa quebra.
    extraSetFlags = [ "--accept-dns=false" ];
    # primeiro boot: `sudo tailscale up --ssh` (autenticação interativa, uma vez)
  };

  users.mutableUsers = false;   # usuários/senhas só via config (passwd no host não persiste)
  # Root com senha SÓ para console/modo de emergência (sulogin recusa root bloqueado). SSH: PermitRootLogin=no.
  users.users.root.hashedPasswordFile = "/etc/secrets/santi.hash";
  users.users.santi = {
    isNormalUser = true;
    uid = 1000;   # determinístico: ownership de /srv e PUID/PGID sobrevivem a reinstalação
    extraGroups = [ "wheel" "docker" ];
    hashedPasswordFile = "/etc/secrets/santi.hash";   # fora do /nix/store (que é world-readable)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDWCI3q/vTKqcuHTbIhIrF5HcccBnOT4oQBaGHM9myWe notebook -> tinyx"
    ];
  };
  # Sem senha no sudo: a fronteira de segurança é a chave SSH, e `nixos-rebuild
  # --target-host --use-remote-sudo` a partir do notebook depende disso.
  security.sudo.wheelNeedsPassword = false;

  # ── Containers ──────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    # containerd image store: default de instalação limpa no Docker 29; evita o graphdriver overlay2
    # legado (que a Docker só suporta oficialmente sobre ext4/xfs) e uma migração com re-pull depois.
    liveRestore = true;   # só stacks detached (Dockge) sobrevivem ao restart do dockerd; os do oci-containers
                          # rodam `docker run` em foreground no unit e são reiniciados de qualquer forma
    autoPrune = { enable = true; dates = "weekly"; randomizedDelaySec = "45min"; };
    daemon.settings = {
      features."containerd-snapshotter" = true;
      # Portas publicadas (-p) FURAM o firewall do NixOS (Docker escreve na chain FORWARD; nixos-fw só filtra
      # INPUT). Com ip=127.0.0.1, `-p 8123:8123` fica em loopback e só o Caddy (443, pelo INPUT) publica.
      # Exceções explícitas por container: `-p 0.0.0.0:53:53` (AdGuard) ou network_mode: host (HA).
      ip = "127.0.0.1";
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };   # logs de container não crescem sem limite
    };
  };
  virtualisation.oci-containers.backend = "docker";
  # systemd-oomd vem ligado mas sem slice monitorado (= inerte). Com o cgroup driver systemd, cada
  # container é um scope em system.slice: sob pressão de memória o oomd mata O CONTAINER (que o Docker
  # reinicia), em vez de o OOM killer do kernel escolher um alvo aleatório após minutos de thrash.
  systemd.oomd.enableSystemSlice = true;
  # Sem isto, o oomd pode escolher docker.service inteiro (todos os containers de uma vez), sshd ou
  # tailscaled como vítima — o critério dele é pressão de reclaim, não tamanho.
  systemd.services = lib.genAttrs [ "docker" "sshd" "tailscaled" "wpa_supplicant" "dhcpcd" ]
    (_: { serviceConfig.ManagedOOMPreference = "avoid"; });
  # earlyoom: 2ª rede de segurança, por outro sinal (RAM+swap livres em %, não pressão PSI). Age quando
  # RAM livre < 5 % E swap livre < 5 % — ou seja, só depois de zswap e partição estarem esgotados.
  # Nunca mata a infra que dá acesso à máquina; dentro de containers, o oomd (acima) chega antes.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
    reportInterval = 0;   # sem relatório periódico no journal (só eventos)
    extraArgs = [ "--avoid" "^(dockerd|containerd|containerd-shim.*|tailscaled|sshd|systemd.*|wpa_supplicant|dhcpcd)$" ];
  };

  # ── Disco ───────────────────────────────────────────────────────────────────
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" "/mnt/dados" ];   # um mountpoint por filesystem
  };
  services.fstrim.enable = true;   # TRIM semanal nos dois SSDs
  services.smartd.enable = true;   # monitora SMART; alerta via wall/journal
  services.journald.extraConfig = "SystemMaxUse=500M";

  # ── Nix ─────────────────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;   # dedup por hardlink no store
  };
  # nix.gc desativado: programs.nh.clean faz o GC (gerações, result/, perfis HM).

  # ── Sistema ─────────────────────────────────────────────────────────────────
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";   # logs/erros em inglês; formatos locais abaixo
  i18n.extraLocaleSettings = {
    LC_TIME = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
  };
  console.keyMap = "br-abnt2";

  environment.systemPackages = with pkgs; [
    vim git tmux htop btop
    lm_sensors smartmontools
    pciutils usbutils ethtool dig
    kitty.terminfo   # TERM=xterm-kitty nas sessões SSH (só o terminfo; kitty em si é do desktop)
    iw         # `iw dev`/`iw wlan0 link`: resgate Wi-Fi (26.05 parou de instalar implicitamente)
    ncdu iotop tcpdump
    compsize   # `compsize /srv` → taxa real de compressão do Btrfs
  ];

  # nh: `nh os switch` resolve nixosConfigurations.$(hostname) neste flake, mostra o diff
  # de gerações antes de ativar e faz GC semanal (gerações + result/ + perfis do HM).
  programs.nh = {
    enable = true;
    flake = "/home/santi/nix-config";
    clean = { enable = true; extraArgs = "--keep-since 7d --keep 5"; };
  };

  # Não mude após a instalação: só diz qual formato de dados de estado o sistema assume.
  system.stateVersion = "26.05";
}
