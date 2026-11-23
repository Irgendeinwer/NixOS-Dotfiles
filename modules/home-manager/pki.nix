{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  desktopEnabled = if osConfig != null then (osConfig.custom.desktop.enable or false) else true;
  defaultCaFile = ../../assets + "/junix-ca.pem";
  localCaCert =
    if osConfig != null then
      (
        if (osConfig.custom.system.security.localCa.enable or false) then
          (osConfig.custom.system.security.localCa.certificateFile or null)
        else
          null
      )
    else if builtins.pathExists defaultCaFile then
      defaultCaFile
    else
      null;
  certutil = "${pkgs.nssTools}/bin/certutil";
  caName = "Junix Internal Root CA";
in
lib.mkIf (desktopEnabled && localCaCert != null) {
  # Chromium and Electron clients (such as Feishin connecting to
  # https://music.junixsrv.internal) consult ~/.pki/nssdb for custom Root CAs
  # rather than /etc/ssl/certs/ca-certificates.crt alone.
  home.activation.junixLocalCaNss = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    nssdb="${config.home.homeDirectory}/.pki/nssdb"
    run mkdir -p -m 0700 "$nssdb"
    if [ ! -f "$nssdb/cert9.db" ]; then
      run ${certutil} -d "sql:$nssdb" -N --empty-password
    fi
    run ${certutil} -d "sql:$nssdb" -D -n ${lib.escapeShellArg caName} >/dev/null 2>&1 || true
    run ${certutil} -d "sql:$nssdb" -A -n ${lib.escapeShellArg caName} -t "C,," -i "${localCaCert}"
  '';
}
