#!/usr/bin/env bash
# install.sh — symlink Ghostty config + custom CSS into ~/.config/ghostty/
# Idempotent: safe to re-run. Backs up existing files.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config/ghostty"

mkdir -p "$TARGET_DIR"

for file in config ghostty-custom.css; do
  src="$PLUGIN_DIR/$file"
  dst="$TARGET_DIR/$file"
  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    mv "$dst" "${dst}.bak.$(date +%s)"
    echo "  backed up $dst"
  fi
  ln -s "$src" "$dst"
  echo "  linked $dst -> $src"
done
