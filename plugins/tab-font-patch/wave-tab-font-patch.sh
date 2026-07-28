#!/usr/bin/env bash
# wave-tab-font-patch.sh
#
# Idempotently patches Wave Terminal's bundled CSS to enlarge the tab-bar
# font (.tab .name { font-size: 11px } -> $TAB_FONT_SIZE px).
# Re-applies itself after Wave auto-updates replace app.asar.
#
# Safe to run repeatedly: detects an already-patched asar and no-ops.
# Original asar is backed up once to app.asar.orig.
#
# Uses `cp` (not `mv`) to replace the asar so it works even while Wave is
# running — the running process has the old asar memory-mapped and is
# unaffected; the next launch picks up the patched content.
#
# The app.asar.unpacked/ directory is NOT touched: it only contains native
# binaries (dist/bin/*) and schema files (dist/schema/*), which are identical
# between the original and patched asar. The repacked asar's header marks
# the same files as unpacked (same --unpack glob), so it stays consistent
# with the existing unpacked dir.
#
# Config:
#   TAB_FONT_SIZE  (default 18)
#   WAVE_APP_PATH  (default /Users/jcallicott/Applications/Wave.app)

set -uo pipefail

TAB_FONT_SIZE="${TAB_FONT_SIZE:-18}"
WAVE_APP_PATH="${WAVE_APP_PATH:-/Users/jcallicott/Applications/Wave.app}"
ASAR="$WAVE_APP_PATH/Contents/Resources/app.asar"
BACKUP="$ASAR.orig"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$PATCH_DIR/patch.log"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG_FILE"; }

# --- preconditions ---------------------------------------------------------
if [[ ! -f "$ASAR" ]]; then
  log "asar not found at $ASAR — Wave not installed? skipping"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  log "ERROR: npx not on PATH — node/npm required"
  exit 0
fi

ASAR_BIN=(npx --yes @electron/asar)
MARKER="/* wave-tab-font-patch:${TAB_FONT_SIZE}px */"
UNPACK_DIR_PATH="$WAVE_APP_PATH/Contents/Resources/app.asar.unpacked"

# --- ensure native binaries are executable ---------------------------------
# @electron/asar extract does NOT preserve executable bits, and a prior version
# of this script once replaced the unpacked dir with one extracted by asar
# (which stripped +x), causing Wave to fail with EACCES on wavesrv.arm64.
# This script no longer touches the unpacked dir, but we defensively chmod
# the binaries on every run in case a Wave update or other tool changed them.
if [[ -d "$UNPACK_DIR_PATH/dist/bin" ]]; then
  chmod +x "$UNPACK_DIR_PATH/dist/bin/"* 2>/dev/null || true
fi

# --- extract ---------------------------------------------------------------
log "extracting asar"
"${ASAR_BIN[@]}" extract "$ASAR" "$WORK_DIR/extracted" 2>/dev/null

CSS_REL=$(find "$WORK_DIR/extracted/dist/frontend/assets" -maxdepth 1 -name 'index-*.css' | head -1)
if [[ -z "$CSS_REL" ]]; then
  log "ERROR: could not locate index-*.css in extracted asar"
  exit 0
fi
CSS_FILE="$WORK_DIR/extracted/dist/frontend/assets/$(basename "$CSS_REL")"

# --- already patched? ------------------------------------------------------
if grep -qF "$MARKER" "$CSS_FILE"; then
  log "already patched at ${TAB_FONT_SIZE}px — no-op"
  exit 0
fi

# --- backup (only first time) ----------------------------------------------
if [[ ! -f "$BACKUP" ]]; then
  cp "$ASAR" "$BACKUP"
  log "backed up original asar -> $BACKUP"
fi

# --- patch -----------------------------------------------------------------
# Replace ONLY the `.tab .name` rule's font-size: 11px. Scoped regex so we
# don't touch the other ~10 unrelated `font-size: 11px` rules in the bundle.
if ! python3 - "$CSS_FILE" "$TAB_FONT_SIZE" "$MARKER" <<'PY'
import re, sys
path, size, marker = sys.argv[1], sys.argv[2], sys.argv[3]
css = open(path).read()
pat = re.compile(r'(\.tab \.name \s*\{[^}]*?font-size:\s*)11px', re.DOTALL)
new, n = pat.subn(lambda m: f'{m.group(1)}{size}px {marker}', css, count=1)
if n != 1:
    print(f'ERROR: expected 1 match, replaced {n}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new)
print(f"patched 1 occurrence -> {size}px")
PY
then
  log "ERROR: python patch step failed"
  exit 0
fi

# --- repack ----------------------------------------------------------------
# Repack with --unpack for native binaries & schema files that must stay on
# disk (matches Wave's original build config). The --unpack glob is evaluated
# relative to cwd, so we cd into the extracted tree first.
log "repacking asar"
( cd "$WORK_DIR/extracted" && \
  "${ASAR_BIN[@]}" pack . "$WORK_DIR/app.asar.new" \
    --unpack "{dist/bin/*,dist/schema/*}" ) 2>/dev/null

if [[ ! -f "$WORK_DIR/app.asar.new" ]]; then
  log "ERROR: repack produced no asar — aborting"
  exit 0
fi

# Sanity: marker must be present in the repacked asar.
"${ASAR_BIN[@]}" extract "$WORK_DIR/app.asar.new" "$WORK_DIR/verify" 2>/dev/null
if ! grep -qF "$MARKER" "$WORK_DIR/verify/dist/frontend/assets/$(basename "$CSS_REL")"; then
  log "ERROR: repacked asar missing marker — aborting without replacing"
  exit 0
fi

# --- replace ---------------------------------------------------------------
# Use `cp` (not `mv`) so this works even while Wave is running. `mv` (rename)
# fails with "Operation not permitted" because the running Wave has the asar
# memory-mapped. `cp` opens-truncates-writes, which macOS allows; the running
# Wave keeps its stale memory mapping and is unaffected. The next Wave launch
# picks up the patched content.
log "replacing asar (cp)"
cp "$WORK_DIR/app.asar.new" "$ASAR"
log "patched .tab .name -> ${TAB_FONT_SIZE}px; takes effect on next Wave launch"
