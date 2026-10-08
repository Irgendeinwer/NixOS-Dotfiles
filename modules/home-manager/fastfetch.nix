{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "${../../assets/icon.png}";
        # Columns wide; height auto-scales to preserve the square aspect.
        # (With neither set, fastfetch renders the 1024px original.)
        width = 40;
        padding = {
          right = 2;
        };
      };
      display = {
        separator = "  ";
        color = "yellow";
      };
      modules = [
        "title"
        "separator"
        "os"
        "host"
        "kernel"
        "uptime"
        "packages"
        "shell"
        "display"
        "wm"
        "terminal"
        "cpu"
        "gpu"
        "memory"
        "disk"
        "break"
        "colors"
      ];
    };
  };
}
