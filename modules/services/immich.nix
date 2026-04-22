{ ... }:
{
  services.immich = {
    enable = true;

    openFirewall = true;
    host = "0.0.0.0";

    mediaLocation = "/media/fun/gallery";
  };
}
