{ pkgs, ... }: {
  home.pointerCursor = {
    enable = true;
    package = pkgs.runCommand "rose-pine-combined" { } ''
      mkdir -p $out/share/icons/BreezeX-RosePine-Linux

      cp -r ${pkgs.rose-pine-cursor}/share/icons/BreezeX-RosePine-Linux/* $out/share/icons/BreezeX-RosePine-Linux/

      HYPR_SRC="${
        pkgs.fetchFromGitHub {
          owner = "ndom91";
          repo = "rose-pine-hyprcursor";
          rev = "main";
          hash = "sha256-ouuA8LVBXzrbYwPW2vNjh7fC9H2UBud/1tUiIM5vPvM=";
        }
      }"
      cp -r $HYPR_SRC/manifest.hl $out/share/icons/BreezeX-RosePine-Linux/
      cp -r $HYPR_SRC/hyprcursors $out/share/icons/BreezeX-RosePine-Linux/
    '';
    name = "BreezeX-RosePine-Linux";
    size = 32;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };
}
