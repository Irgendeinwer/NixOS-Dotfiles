{ ... }:
{
  programs.git = {
	enable = true;
	userName = "Irgendeinwer";
	userEmail = "irgendeinwer@proton.me";
	extraConfig = {
		init.defaultBranch = "main";
	};
  };
}
