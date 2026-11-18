{ lib }:
{
  monitors,
  notifySend,
}:
let
  # JSON string escapes such as \u0001 are not valid Lua 5.1 escapes. Quote
  # strings directly, using three-digit decimal escapes for control bytes so
  # that a following digit cannot be absorbed into the escape.
  hexDigits = "0123456789abcdef";
  controls = lib.range 1 31; # Nix strings cannot contain a NUL byte.
  controlChar =
    n:
    builtins.fromJSON (
      ''"\u00''
      + builtins.substring (n / 16) 1 hexDigits
      + builtins.substring (lib.mod n 16) 1 hexDigits
      + ''"''
    );
  luaString =
    value:
    ''"${
      builtins.replaceStrings
        (
          [
            "\\"
            "\""
          ]
          ++ map controlChar controls
        )
        (
          [
            "\\\\"
            "\\\""
          ]
          ++ map (n: "\\${if n < 10 then "00" else "0"}${toString n}") controls
        )
        value
    }"'';

  formatMonitor =
    m:
    let
      bitdepthStr =
        if (m.bitdepth or null) != null then "\n      bitdepth = ${toString m.bitdepth}," else "";
      cmStr = if (m.cm or null) != null then "\n      cm = ${luaString m.cm}," else "";
      sdrbrightnessStr =
        if (m.sdrbrightness or null) != null then
          "\n      sdrbrightness = ${toString m.sdrbrightness},"
        else
          "";
    in
    ''
      hl.monitor({
        output = ${luaString m.output},
        mode = ${luaString (m.mode or "preferred")},
        position = ${luaString (m.position or "auto")},
        scale = ${toString (m.scale or 1)},${bitdepthStr}${cmStr}${sdrbrightnessStr}
      })
    '';

  hdrMonitor = lib.findFirst (m: m.hdr or false) null monitors;
  hasHdr = hdrMonitor != null;
  hdrMode = if hasHdr then (hdrMonitor.mode or "preferred") else "preferred";
  hdrPos = if hasHdr then (hdrMonitor.position or "auto") else "auto";
  hdrScale = if hasHdr then toString (hdrMonitor.scale or 1) else "1";
  hdrBitdepth =
    if hasHdr && (hdrMonitor.bitdepth or null) != null then toString hdrMonitor.bitdepth else "10";
  hdrBaseCm = if hasHdr && (hdrMonitor.cm or null) != null then hdrMonitor.cm else "srgb";
in
{
  layout = lib.concatMapStringsSep "\n\n" formatMonitor (
    if monitors == [ ] then [ { output = ""; } ] else monitors
  );

  # Hyprland's toggle uses the first monitor marked hdr = true.
  hdrToggle = lib.optionalString hasHdr ''
    -- HDR toggle for the monitor marked `hdr = true`
    local hdr_on = false
    local function toggle_hdr()
      hdr_on = not hdr_on
      hl.monitor({
        output = ${luaString hdrMonitor.output},
        mode = ${luaString hdrMode},
        position = ${luaString hdrPos},
        scale = ${hdrScale},
        bitdepth = ${hdrBitdepth},
        cm = hdr_on and "hdr" or ${luaString hdrBaseCm},
        sdrbrightness = hdr_on and 1.2 or 1.0,
      })

      local status = hdr_on and "HDR Enabled (${hdrBitdepth}-bit)" or "SDR Mode (${hdrBitdepth}-bit)"
      hl.exec_cmd(string.format([[${notifySend} "Display" "%s" -t 5000]], status))
    end
    hl.bind(mainMod .. " + SHIFT + H", toggle_hdr)
  '';
}
