#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash

set -e
echo -e "This script will test your configuration, add everything in ~/dotfiles/ to git, commit the changes and rebuild your system\n"
font="rozzo"

figlet -tc -f $font Testing... | lolcat
read -rp "Enter options to pass to the command (default: none): " options
sudo nixos-rebuild test --flake ~/dotfiles/#$HOSTNAME $options
echo -e "\n"

figlet -tc -f $font Committing... | lolcat
cd ~/dotfiles/
git add *
read -rp "Enter git commit message: " message
git commit -m "$message" -a

echo -e "\n"

figlet -tc -f $font Applying... | lolcat
sudo nixos-rebuild switch --flake ~/dotfiles/#$HOSTNAME $options
