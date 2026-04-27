{
  programs.nixvim.plugins.markview = {
    enable = true;

    settings = {
      preview = {
        modes = [
          "n"
          "i"
          "no"
          "c"
        ];

        enable_hybrid_mode = true;

        hybrid_modes = [
          "n"
          "i"
        ];
      };

      checkboxes = {
        enable = true;
        checked = {
          text = "✔";
          hl = "MarkviewCheckboxChecked";
        };
        unchecked = {
          text = "✘";
          hl = "MarkviewCheckboxUnchecked";
        };
      };

      links = {
        enable = true;
      };
    };
  };
}
