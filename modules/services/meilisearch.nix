{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.meilisearch;
in
{
  options.custom.services.meilisearch = {
    enable = lib.mkEnableOption "Meilisearch fast search engine";
  };

  config = lib.mkIf cfg.enable {
    services.meilisearch = {
      enable = true;
    };
  };
}
