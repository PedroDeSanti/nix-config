# T3 Code server as a user service: it must run as santi to use the Claude Code login
# in ~/.claude. Loopback only; Caddy publishes it as t3.lab.desanti.dev (system side in
# hosts/tinyx/services/t3code.nix). State lives in ~/.t3 (backed up with /home).
{ pkgs, ... }: {
  # `t3` (pairing links, session admin) and `claude` (auth login) on the shell PATH.
  home.packages = [ pkgs.t3code pkgs.claude-code ];

  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code server";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs.t3code}/bin/t3 serve --host 127.0.0.1 --port 3773 --no-browser";
      WorkingDirectory = "%h";
      Restart = "always";
      RestartSec = 5;
      # Upstream's unit: stop the server, let agent processes wind down on their own.
      KillMode = "mixed";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
