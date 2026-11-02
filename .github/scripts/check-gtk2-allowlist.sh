#!/usr/bin/env bash
set -euo pipefail

# This strict variant intentionally overrides the GTK 2 warning. The check
# should fail only while a package marked broken as gtk+ is still required.
if output=$(nix eval .#nixosConfigurations.junixosStrictGtk2.config.system.build.toplevel.drvPath --show-trace 2>&1); then
  echo "The strict junixos evaluation passed; remove the obsolete GTK 2 exception from modules/nixos/base.nix."
  exit 1
fi

if ! grep -Fq "Refusing to evaluate package 'gtk+" <<< "$output"; then
  echo "The strict evaluation failed for an unexpected reason:"
  printf '%s\n' "$output"
  exit 1
fi

echo "GTK 2 is still marked broken and required by the configuration; the exception remains necessary."
