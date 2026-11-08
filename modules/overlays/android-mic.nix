final: prev: {
  # Temporary AWS-LC dependency fix; fail evaluation once upstream no longer needs it.
  android-mic =
    assert prev.lib.assertMsg (prev.lib.versionOlder prev.android-mic.version "2.2.12")
      "android-mic has reached 2.2.12; remove modules/overlays/android-mic.nix.";
    prev.android-mic.overrideAttrs (old: {
      buildInputs =
        assert prev.lib.assertMsg (
          !(builtins.any (input: prev.lib.getName input == "aws-lc") (old.buildInputs or [ ]))
        ) "android-mic already includes aws-lc; remove modules/overlays/android-mic.nix.";
        (old.buildInputs or [ ]) ++ [ final.aws-lc ];
    });
}
