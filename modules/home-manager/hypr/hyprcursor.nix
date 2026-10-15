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
          # A commit, not a branch: the hash only matches this exact tree, so
          # a branch would break the next fresh fetch once upstream moves on.
          rev = "4b02963d0baf0bee18725cf7c5762b3b3c1392f1";
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
