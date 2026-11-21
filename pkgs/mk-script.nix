# Shared builders for standalone CLI scripts in `pkgs/scripts/`.
# Shell scripts are validated with ShellCheck via `writeShellApplication`;
# Python scripts are byte-compiled and linted with Ruff at build time.
{
  lib ? pkgs.lib,
  pkgs,
}:
{
  mkShellScript =
    {
      name,
      src,
      runtimeInputs ? [ ],
      excludeShellChecks ? [ ],
      meta ? { },
    }:
    let
      drv = pkgs.writeShellApplication {
        inherit name runtimeInputs excludeShellChecks;
        text = builtins.readFile src;
      };
    in
    drv.overrideAttrs (old: {
      meta = (old.meta or { }) // meta // { mainProgram = name; };
    });

  mkPythonScript =
    {
      name,
      src,
      python ? pkgs.python3,
      pythonPackages ? (_: [ ]),
      runtimeInputs ? [ ],
      ruffIgnore ? [ ],
      meta ? { },
    }:
    let
      pyEnv = python.withPackages pythonPackages;
      ignoreFlag =
        if ruffIgnore == [ ] then
          ""
        else
          "--ignore ${lib.escapeShellArg (lib.concatStringsSep "," ruffIgnore)}";
      pathWrapper =
        if runtimeInputs == [ ] then "" else "--prefix PATH : ${lib.makeBinPath runtimeInputs}";
    in
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pkgs.makeWrapper
          pkgs.ruff
          pyEnv
        ];
        meta = { mainProgram = name; } // meta;
      }
      ''
        mkdir -p "$out/libexec" "$out/bin"
        cp ${src} "$out/libexec/${name}.py"
        ruff check --no-cache --select E9,F ${ignoreFlag} "$out/libexec/${name}.py"
        python3 -m py_compile "$out/libexec/${name}.py"
        makeWrapper "${pyEnv}/bin/python3" "$out/bin/${name}" \
          --add-flags "-B $out/libexec/${name}.py" \
          ${pathWrapper}
      '';
}
