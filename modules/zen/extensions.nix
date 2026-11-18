{ lib }:
let
  # The set is declarative, but Zen/Firefox continues to update each add-on.
  # normal_installed allows an installed extension to remain disabled; it
  # prevents removal from about:addons while the policy is in place.
  addons = [
    "{34daeb50-c2d2-4f14-886a-7160b24d66a4}" # YouTube Shorts Block
    "{0d7cafdd-501c-49ca-8ebb-e3341caaa55e}" # YouTube NonStop
    "open-in-mpv@binarynoise.de"
    "{91aa3897-2634-4a8a-9092-279db23a7689}" # Zen Internet
    "sponsorBlocker@ajay.app"
    "deArrow@ajay.app"
    "{9350bc42-47fb-4598-ae0f-825e3dd9ceba}" # Absolute Enable Right Click & Copy
    "firefox-extension@steamdb.info"
    "{5d554479-7cc4-487f-bd25-d8fc67a42602}" # FMHY SafeGuard
    "{1be309c5-3e4f-4b99-927d-bb500eb4fa88}" # Augmented Steam
    "{30280527-c46c-4e03-bb16-2e3ed94fa57c}" # ProtonDB for Steam
    "keepassxc-browser@keepassxc.org"
    "adnauseam@rednoise.org"
    "addon@darkreader.org"
    "seventv-next@7tv.app"
    "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" # Return YouTube Dislike
    "{b11bea1f-a888-4332-8d8a-cec2be7d24b9}" # Snowflake
  ];
in
lib.genAttrs addons (id: {
  installation_mode = "normal_installed";
  # AMO accepts add-on IDs in the latest endpoint. Escape braces and @ as a
  # path segment, rather than trusting an ambiguous or mutable display name.
  install_url = "https://addons.mozilla.org/firefox/downloads/latest/${lib.escapeURL id}/latest.xpi";
})
