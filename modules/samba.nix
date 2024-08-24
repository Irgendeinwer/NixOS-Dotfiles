{ pkgs, ... }:
{
	environment.systemPackages = with pkgs; [
		samba
	];
	services.samba = {
		enable = true;
		securityType = "user";
		openFirewall = true;
		extraConfig = ''
			workgroup = LINDNER
			server string = smbnix
			netbios name = smbnix
  			hosts allow = 192.168.0. 127.0.0.1 localhost
  			hosts deny = 0.0.0.0/0
		'';
		shares = {
			public = {
				path = "/media/spiele/Videos";
				browseable = "yes";
				"read only" = "yes";
				"guest ok" = "yes";
  			};
		};
	};

	services.samba-wsdd = {
		enable = true;
	};
}
