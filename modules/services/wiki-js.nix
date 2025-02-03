{ ... }:
{
  services.wiki-js = {
    enable = true;
    settings = {
	port = 80;
	db = {
	    host = "/run/postgresql";
	};
    };
  };
}
