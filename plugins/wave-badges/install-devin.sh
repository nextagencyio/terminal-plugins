#!/bin/bash
# Wire wave-badges into Devin CLI. Idempotent — safe to re-run.
#
# Devin's hooks live in ~/.config/devin/config.json (Claude Code-style schema).
# This script symlinks the badge script to a stable path and merges hook
# entries for the five lifecycle events, replacing any previous wave-badge
# entries so upgrades don't duplicate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${DEVIN_CONFIG:-$HOME/.config/devin/config.json}"
BIN="$HOME/.local/bin/wave-badge"

command -v jq >/dev/null || { echo "jq is required (brew install jq)"; exit 1; }
[ -f "$CFG" ] || { echo "Devin config not found at $CFG"; exit 1; }

mkdir -p "$HOME/.local/bin"
ln -sf "$SCRIPT_DIR/bin/wave-badge" "$BIN"

WB="\"\$HOME/.local/bin/wave-badge\" Devin"

jq --arg wb "$WB" '
  def strip: (.hooks //= []) | .hooks |= map(select((.command // "") | test("wave-badge") | not));
  def add(state): .hooks += [{"type": "command", "command": ($wb + " " + state)}];
  .hooks.PermissionRequest //= [{"matcher": "", "hooks": []}] |
  .hooks.Stop              //= [{"matcher": "", "hooks": []}] |
  .hooks.UserPromptSubmit  //= [{"matcher": "", "hooks": []}] |
  .hooks.PostToolUse       //= [{"matcher": "", "hooks": []}] |
  .hooks.SessionStart      //= [{"matcher": "", "hooks": []}] |
  .hooks.SessionEnd        //= [{"matcher": "", "hooks": []}] |
  .hooks.PermissionRequest[0] |= (strip | add("attention")) |
  .hooks.Stop[0]              |= (strip | add("done")) |
  .hooks.UserPromptSubmit[0]  |= (strip | add("working")) |
  .hooks.PostToolUse[0]       |= (strip | add("working")) |
  .hooks.SessionStart[0]      |= (strip | add("clear")) |
  .hooks.SessionEnd[0]        |= (strip | add("clear"))
' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"

echo "wave-badges wired into Devin CLI ($CFG). Restart Devin sessions to pick it up."
