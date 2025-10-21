{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Irgendeinwer";
      user.email = "irgendeinwer@proton.me";
      extraConfig = {
        init.defaultBranch = "main";
      };
    };
  };
}
