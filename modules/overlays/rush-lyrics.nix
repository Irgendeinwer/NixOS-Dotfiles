final: prev: {
  rush-lyrics = final.callPackage (
    {
      appimageTools,
      fetchurl,
      lib,
    }:
    let
      pname = "rush-lyrics";
      version = "6.4.0";

      src = fetchurl {
        url = "https://github.com/shub39/Rush/releases/download/${version}/rush-${version}-linux-x86_64.AppImage";
        hash = "sha256-R8eX9QGkTyIrynIm3m6MOwp3x8HAxw+5yGH7FAC/MP4=";
      };

      appimageContents = appimageTools.extractType2 {
        inherit pname version src;
      };
    in
    appimageTools.wrapType2 {
      inherit pname version src;

      extraInstallCommands = ''
        # Copy extracted desktop file
        install -m 444 -D ${appimageContents}/*.desktop $out/share/applications/rush-lyrics.desktop

        # Rewrite Exec and Icon entries to match package name
        sed -i 's|^Exec=.*|Exec=rush-lyrics|g' $out/share/applications/rush-lyrics.desktop
        sed -i 's|^Icon=.*|Icon=rush-lyrics|g' $out/share/applications/rush-lyrics.desktop

        # Copy PNG icon from AppImage
        install -m 444 -D ${appimageContents}/*.png $out/share/icons/hicolor/512x512/apps/rush-lyrics.png || true
      '';

      meta = with lib; {
        description = "✨ App to search, save and share lyrics like spotify!";
        homepage = "https://github.com/shub39/Rush";
        license = licenses.gpl3Only;
        platforms = [ "x86_64-linux" ];
      };
    }
  ) { };
}
