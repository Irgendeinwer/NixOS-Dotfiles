final: prev: {
  custom =
    (prev.custom or { })
    // (import ../../pkgs/scripts { pkgs = final; })
    // {
      without-userns = final.callPackage ../../pkgs/without-userns.nix { };
    };
}
