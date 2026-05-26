{ pkgs, ... }:

{
  services.flatpak.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/flatpak/overrides 0755 root root - -"
    
    # Override for Bottles: Isolated to ~/UntrustedGames (Read/Write)
    "L+ /var/lib/flatpak/overrides/com.usebottles.bottles - - - - ${pkgs.writeText "bottles-override" ''
      [Context]
      filesystems=!home;!host;~/UntrustedGames:create;
    ''}"

    # Override for Sandboxed Steam: Isolated to ~/UntrustedGames (Read/Write)
    "L+ /var/lib/flatpak/overrides/com.valvesoftware.Steam - - - - ${pkgs.writeText "steam-override" ''
      [Context]
      filesystems=!home;!host;~/UntrustedGames:create;
    ''}"
  ];

  systemd.services.configure-flatpak-bottles = {
    description = "Declarative Flatpak installation for Steam and Bottles";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "setup-bottles-steam" ''
        # Ensure Flathub repository is registered
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        
        # Install Bottles
        ${pkgs.flatpak}/bin/flatpak install -y flathub com.usebottles.bottles
        
        # Install Sandboxed Steam
        ${pkgs.flatpak}/bin/flatpak install -y flathub com.valvesoftware.Steam
      '';
    };
  };
}
