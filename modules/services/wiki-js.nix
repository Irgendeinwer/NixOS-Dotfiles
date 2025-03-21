{ ... }:
{
  systemd.services.wiki-js = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };

  services.wiki-js = {
    enable = true;
    settings = {
      port = 8080;
      db = {
        db = "wiki-js";
        host = "/run/postgresql";
        type = "postgres";
        user = "wiki-js";
      };
    };
  };
}
