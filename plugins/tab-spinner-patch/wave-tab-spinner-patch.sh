#!/usr/bin/env bash
# wave-tab-spinner-patch.sh
#
# Replaces Wave Terminal's spinning tab "waiting" badge with a subtle
# opacity-pulsing icon. The default tab badge for a running/waiting block
# is a Font Awesome icon with the `fa-spin` modifier (a continuous 360°
# rotation), which gets visually tiring. This patch swaps that rotation
# for a gentle opacity pulse (0.4 <-> 1.0 over 1.8s, ease-in-out) on tab
# badges only — other spinners elsewhere in the app are untouched.
#
# How it works:
#   1. JS  — in the shared `TabBadges` component (the single render path
#            for BOTH the top tab bar and the left sidebar vtab), the
#            firstBadge <i> className is built from
#              makeIconClass(firstBadge.icon, true, { defaultIcon: "circle-small" }) + " text-[12px]"
#            We append `.replace("fa-spin", "wave-tab-pulse")` so any
#            spinning tab badge icon pulses instead of rotating.
#   2. CSS — append a `.wave-tab-pulse` animation + `@keyframes` rule.
#
# Scope: tab badges only. Block-header spinners, secret-dialog spinners,
# app-list spinners, etc. are NOT affected (they use different render
# paths that don't go through TabBadges' firstBadge <i>).
#
# Safe to run repeatedly: detects an already-patched asar and no-ops.
# Original asar is backed up once to app.asar.orig (shared with other
# wave-* patch scripts — only the first one to run creates it).
#
# Uses `cp` (not `mv`) to replace the asar so it works even while Wave is
# running; the next launch picks up the patched content.
#
# Config:
#   WAVE_APP_PATH  (default /Users/jcallicott/Applications/Wave.app)
#   PULSE_DURATION (default 1.8s)
#   PULSE_MIN_OPACITY (default 0.4)

set -uo pipefail

WAVE_APP_PATH="${WAVE_APP_PATH:-/Users/jcallicott/Applications/Wave.app}"
PULSE_DURATION="${PULSE_DURATION:-1.8s}"
PULSE_MIN_OPACITY="${PULSE_MIN_OPACITY:-0.4}"
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
CSS_MARKER="/* wave-tab-spinner-patch */"
JS_MARKER="wave-tab-pulse"
UNPACK_DIR_PATH="$WAVE_APP_PATH/Contents/Resources/app.asar.unpacked"

# --- ensure native binaries are executable ---------------------------------
if [[ -d "$UNPACK_DIR_PATH/dist/bin" ]]; then
  chmod +x "$UNPACK_DIR_PATH/dist/bin/"* 2>/dev/null || true
fi

# --- extract ---------------------------------------------------------------
log "extracting asar (tab-spinner)"
"${ASAR_BIN[@]}" extract "$ASAR" "$WORK_DIR/extracted" 2>/dev/null

CSS_REL=$(find "$WORK_DIR/extracted/dist/frontend/assets" -maxdepth 1 -name 'index-*.css' | head -1)
if [[ -z "$CSS_REL" ]]; then
  log "ERROR: could not locate index-*.css in extracted asar"
  exit 0
fi
CSS_FILE="$WORK_DIR/extracted/dist/frontend/assets/$(basename "$CSS_REL")"

JS_BASENAME="$(grep -oE 'src="\./assets/(index-[^"]+\.js)"' "$WORK_DIR/extracted/dist/frontend/index.html" | sed -E 's/^src="\.\/assets\///; s/"$//')"
if [[ -z "$JS_BASENAME" ]]; then
  log "ERROR: could not locate entry-point index-*.js in index.html"
  exit 0
fi
JS_FILE="$WORK_DIR/extracted/dist/frontend/assets/$JS_BASENAME"

# --- check what's already patched ------------------------------------------
CSS_DONE=0
JS_DONE=0
grep -qF "$CSS_MARKER" "$CSS_FILE" && CSS_DONE=1
grep -qF "$JS_MARKER" "$JS_FILE" && JS_DONE=1

if [[ $CSS_DONE -eq 1 && $JS_DONE -eq 1 ]]; then
  log "already patched (tab-spinner pulse) — no-op"
  exit 0
fi

# --- backup (only first time, shared across wave-* patches) ----------------
if [[ ! -f "$BACKUP" ]]; then
  cp "$ASAR" "$BACKUP"
  log "backed up original asar -> $BACKUP"
fi

CHANGED=0

# --- patch CSS: append pulse keyframes + class -----------------------------
if [[ $CSS_DONE -eq 0 ]]; then
  python3 - "$CSS_FILE" "$CSS_MARKER" "$PULSE_DURATION" "$PULSE_MIN_OPACITY" <<'PY'
import sys
path, marker, duration, min_opacity = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
css = open(path).read()
block = (
    f"\n{marker}\n"
    f".wave-tab-pulse{{-webkit-animation:wave-tab-pulse {duration} ease-in-out infinite;"
    f"animation:wave-tab-pulse {duration} ease-in-out infinite}}\n"
    f"@-webkit-keyframes wave-tab-pulse{{0%,100%{{-webkit-opacity:{min_opacity};opacity:{min_opacity}}}50%{{-webkit-opacity:1;opacity:1}}}}\n"
    f"@keyframes wave-tab-pulse{{0%,100%{{opacity:{min_opacity}}}50%{{opacity:1}}}}\n"
)
open(path, 'w').write(css + block)
print("appended pulse keyframes")
PY
  log "patched CSS: appended .wave-tab-pulse (${PULSE_DURATION}, min opacity ${PULSE_MIN_OPACITY})"
  CHANGED=1
else
  log "CSS already patched — skipping"
fi

# --- patch JS: TabBadges firstBadge <i> fa-spin -> wave-tab-pulse ----------
# The exact className expression in the shared TabBadges component. Replacing
# fa-spin with wave-tab-pulse here covers BOTH top tabs and the left sidebar
# vtab, since both render tab badges through this single component.
if [[ $JS_DONE -eq 0 ]]; then
  if python3 - "$JS_FILE" "$JS_MARKER" <<'PY'
import sys
path, marker = sys.argv[1], sys.argv[2]
js = open(path).read()
old = 'makeIconClass(firstBadge.icon, true, { defaultIcon: "circle-small" }) + " text-[12px]"'
new = '(makeIconClass(firstBadge.icon, true, { defaultIcon: "circle-small" }) + " text-[12px]").replace("fa-spin", "' + marker + '")'
n = js.count(old)
if n != 1:
    print(f'ERROR: expected 1 match of TabBadges firstBadge className, found {n}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(js.replace(old, new, 1))
print("patched TabBadges firstBadge: fa-spin -> " + marker)
PY
  then
    log "patched JS TabBadges firstBadge: fa-spin -> $JS_MARKER"
    CHANGED=1
  else
    log "ERROR: JS tab-spinner patch step failed"
    exit 0
  fi
else
  log "JS tab-spinner already patched — skipping"
fi

if [[ $CHANGED -eq 0 ]]; then
  log "no changes needed — no-op"
  exit 0
fi

# --- repack ----------------------------------------------------------------
log "repacking asar"
( cd "$WORK_DIR/extracted" && \
  "${ASAR_BIN[@]}" pack . "$WORK_DIR/app.asar.new" \
    --unpack "{dist/bin/*,dist/schema/*}" ) 2>/dev/null

if [[ ! -f "$WORK_DIR/app.asar.new" ]]; then
  log "ERROR: repack produced no asar — aborting"
  exit 0
fi

# Sanity: markers must be present in the repacked asar.
"${ASAR_BIN[@]}" extract "$WORK_DIR/app.asar.new" "$WORK_DIR/verify" 2>/dev/null
VERIFY_CSS="$WORK_DIR/verify/dist/frontend/assets/$(basename "$CSS_REL")"
VERIFY_JS="$WORK_DIR/verify/dist/frontend/assets/$JS_BASENAME"
if [[ $CSS_DONE -eq 0 ]] && ! grep -qF "$CSS_MARKER" "$VERIFY_CSS"; then
  log "ERROR: repacked asar missing CSS marker — aborting without replacing"
  exit 0
fi
if [[ $JS_DONE -eq 0 ]] && ! grep -qF "$JS_MARKER" "$VERIFY_JS"; then
  log "ERROR: repacked asar missing JS marker — aborting without replacing"
  exit 0
fi

# --- replace ---------------------------------------------------------------
log "replacing asar (cp)"
cp "$WORK_DIR/app.asar.new" "$ASAR"
log "patched: tab waiting spinner -> subtle opacity pulse (${PULSE_DURATION}, min ${PULSE_MIN_OPACITY}); takes effect on next Wave launch"
