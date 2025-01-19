# Personal dotfiles of Irgendeinwer

These are my dotfiles for NixOS (First try!!!). You can use them but I don't recommend it (obviously).

# File tree:

```
.
├── flake.lock
├── flake.nix
├── hosts
│   ├── junixbook
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── home.nix
│   └── junixos
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── home.nix
├── modules
│   ├── home-manager
│   │   ├── git.nix
│   │   ├── gtk.nix
│   │   ├── hypr
│   │   │   ├── hypridle.nix
│   │   │   ├── hyprland.nix
│   │   │   ├── hyprlock.nix
│   │   │   └── hyprpaper.nix
│   │   ├── rofi
│   │   │   ├── gruvbox-material.rasi
│   │   │   └── rofi.nix
│   │   └── zsh.nix
│   ├── nixos
│   │   ├── android.nix
│   │   ├── bluetooth.nix
│   │   ├── direnv.nix
│   │   ├── flakes.nix
│   │   ├── fonts.nix
│   │   ├── gaming.nix
│   │   ├── greetd.nix
│   │   ├── hypr.nix
│   │   ├── i2p.nix
│   │   ├── pkgs
│   │   │   ├── browsers.nix
│   │   │   ├── flexing.nix
│   │   │   ├── messaging.nix
│   │   │   └── streaming.nix
│   │   ├── pkgs.nix
│   │   ├── plymouth.nix
│   │   ├── sound.nix
│   │   └── virt.nix
│   ├── nixvim
│   │   ├── keybinds.nix
│   │   ├── nixvim.nix
│   │   ├── options.nix
│   │   └── plugins
│   │       ├── default.nix
│   │       ├── lsp.nix
│   │       └── telescope.nix
│   ├── scripts
│   │   └── rebuild.sh
│   └── services
│       ├── ArchiSteamFarm.nix
│       ├── jellyfin.nix
│       └── services.nix
├── README.md
└── wallpapers
    ├── gruvbox_girl.png
    ├── nix-flake-gruvbox.png
    ├── NixOS.png
    ├── wallhaven-2e2xyx.jpg
    └── Witcher_IV_Wallpaper_01_13840x2160_EN.jpeg
```

# TODO

Completely rework the dotfiles as this was my first try with NixOS :)

---
# Credits:

 - Nix Community - I copied most of my configs :)
