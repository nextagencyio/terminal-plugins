#!/bin/bash
# Wire wave-badges into opencode. Idempotent — safe to re-run.
# Symlinks the badge script to a stable path and the plugin into
# opencode's global plugin directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/opencode/plugins"
ln -sf "$SCRIPT_DIR/bin/wave-badge" "$HOME/.local/bin/wave-badge"
ln -sf "$SCRIPT_DIR/opencode/wave-badge.js" "$HOME/.config/opencode/plugins/wave-badge.js"

echo "wave-badges wired into opencode. Restart opencode sessions to pick it up."
