{ ... }:
{
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 8d --keep 6";
    flake = "/home/julian/dotfiles";
  };
}
