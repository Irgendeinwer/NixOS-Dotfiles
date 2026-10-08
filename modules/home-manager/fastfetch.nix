{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "${../../assets/icon.png}";
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
