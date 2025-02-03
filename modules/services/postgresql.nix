{ pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17_jit;

    ensureDatabases = [ "wiki-js" ];
    ensureUsers = [{
	name = "wiki-js";
	ensureDBOwnership = true;
    }];
  };
}
