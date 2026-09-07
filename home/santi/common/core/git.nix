{ ... }: {
  programs.git = {
    enable = true;
    userName = "PedroDeSanti";
    userEmail = "phmartinsanti@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
