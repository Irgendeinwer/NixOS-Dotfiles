{ pkgs }:

pkgs.runCommand "royal-mashup-preset-profiles"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    for profile in calm balanced intense; do
      mkdir -p "$out/$profile"
      ${pkgs.python3}/bin/python3 ${./generate-royal-profile.py} \
        --profile "$profile" \
        --source ${./royal-mashup-remix.milk} \
        --module ${./royal-mashup-remix.butterchurn.ts} \
        --output-dir "$out/$profile"
    done
  ''
